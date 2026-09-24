# The premium feel: research and roadmap (2026-09-24)

The owner asked: *"do more research and really study games and summoners war
and come up with more upgrades to enhance the feel and look of the game"*.
Before that he said: *"Make these upgrades REALLY well and really focus and put
your best design hat on. I really want this to have a premium feel."* He sent
two Summoners War battle frames as the target.

Six researchers each took one area: the battle, art direction, the menus, the
summon, the island and the progress around it, and sound. Each read our code,
looked at the CI frames of run 241, and studied Summoners War first, then
Genshin Impact, Honkai: Star Rail, Epic Seven, Arknights, Raid, AFK
Arena/Journey and Cookie Run: Kingdom, along with the game-feel literature.
This file merges what they brought back into one plan.

**Already being done elsewhere.** A separate job is moving the battle camera to
the owner's angle and doing the clean lighting, texture clarity, unit shadows
and designed arena floors. None of that is proposed here; everything here
builds on it. The motion roll-out (`Docs/MOTION.md`: each family its own
attacks and its own victory pose) is also its own job. Several items below get
better when it lands, and they say so.

**The art director's pass (the same day).** A seventh reader went through the
merged plan as the owner's hardest critic, checked each item against the code
and the frames, and changed it in four ways:

- **Areas added that nobody studied:** the unit sheet (W1.10), building a
  lineup (W2.25), the way into a fight (W2.24), frame pacing (W2.26),
  readability and touch on the smallest phone (W2.27), the arena as a contest
  (W2.28) and the first five minutes (W3.30).
- **Items corrected where they said something already built was missing.**
  Crits already float in gold with a "!", glancing hits in slate, and RESIST,
  COUNTER, EXTRA TURN, each status's name and the skill's name already float
  over the unit (`BattleSceneController.swift:950` and `1090–1165`). The
  hit-stop already grows with the hit's weight. W1.2, W1.3, W1.9 and W2.22 now
  say what is really new.
- **A defect found:** the 120 Hz choice built on the feature day can never
  appear on an iPhone, because the Info.plist key it checks for is not in the
  project (W1.8).
- **The ranking changed.** Figure-first light is lighting, and a lighting job
  is running now, so it is handed to that job as **L1** instead of taking a
  place in the top ten. Its place goes to the unit sheet: the serious remake of
  the whole roster is the owner's largest purchase, and the screen players open
  most still shows only a card. Ties are now broken by how often a player sees
  the thing, so the press language, which is on every tap, moves up to fourth.

**How sure the facts are.** The network policy blocks almost every wiki,
including the Summoners War fandom wiki, namu.wiki, GameWith, ArtStation, GDC
Vault's PDFs, BlueStacks and archive.org. The researchers worked from what they
could reach, and every fact below carries one of three marks:

- **[checked]**: seen in a search result's summary, in a page that loaded, in
  the owner's two frames, or measured here.
- **[recalled]**: from memory of playing or reading, and not confirmed here.
- **[ours]**: read in our own code or CI frames.

---

## 1. What makes the genre feel premium

Ten principles, each with its evidence. None is about how many polygons a model
has. They are about attention, rhythm and response.

**1. The figure is the most coloured, best-separated thing on the screen.**
Measured on the owner's two Summoners War frames [checked, measured here]:

- The median pixel saturation is only 0.20–0.24.
- The 95th percentile is 0.82–0.87, and about 15% of pixels are over 0.6.

So the set is grey-blue stone with gold and cyan trim, and the colour is spent
on the monsters and a few glowing accents. Genshin lights its characters apart
from the scene [recalled]. Stylised art-direction guides call this compressing
the set's values and keeping the figure's silhouette clear [checked].

**2. Every touch answers at once, in picture, sound and feel.** Swink's *Game
Feel* defines polish as the effects that "sell the perception of real-time
control" [checked]. Jonasson and Purho's *Juice it or lose it* puts tweening,
squash and stretch, particles, shake and sound on every event [checked].
Guidelines for UI motion give a tap 100–200 ms of response and keep bounce for
successes [checked].

**3. Big moments stop time for a moment.** Some examples [all checked]:

- In Smash Bros., both fighters freeze on a hit, the freeze grows with the
  damage, and the victim SHAKES inside it.
- Final Fight freezes six frames on every hit.
- Vlambeer's *The Art of Screenshake* pauses a frame or two on a kill.
- Eiserloh's GDC 2016 talk shows that a 3D camera shake should be rotation
  driven by smooth noise and should grow with "trauma squared".

**4. Suspense climbs, and rarity has a colour.**

- Genshin's wish meteor turns "from blue or purple to gold" [checked].
- Summoners War gives 4★ and 5★ the same animation on purpose, so the player
  asks "is it a 4 or a 5?" [checked, Com2uS forum summary].
- A 5★ in Summoners War is said to have a lightning tell [checked by a video
  title only].
- Star Rail's 5★ music is more upbeat [checked].
- Raid colours its shards green, blue, purple and gold [checked].
- Articles on gacha psychology put the peak of excitement *during* the
  animation, not at the reveal [checked].

**5. Rewards travel to where they are kept.** "Currency flows from the claim
button to the wallet's place in the UI" [checked, a summary of Game Economist
Consulting]. Cookie Run: Kingdom flies a won item to the top bar [checked].

**6. Nothing important is silent.** Both *Juice it or lose it* and Vlambeer's
talk count sound as half of the impact [checked]. Genshin records each region
with that culture's instruments [checked]. Summoners War has separate music
for the summon, the arena and each dungeon [checked: the soundtrack's track
names].

**7. The place is alive.**

- Summoners War's island has monsters wandering on it, and Ellia walks it with
  speech bubbles about events and daily reminders [checked].
- Cookie Run's cookies walk the kingdom and use the decorations [checked].
- The owner's second frame shows floating debris, a light beam rising from a
  fountain, and statues with glowing cyan runes [checked].

**8. Respect the repeat player's time without deleting the moment.** Summoners
War offers ×1, ×2 and ×3 battle speed [checked], and added the 10× summon in
patch 6.6.3 because single pulls were slow [checked]. Genshin's skip still
shows a 5★ [recalled].

**9. One hand designs everything.** HoYoverse runs one design system across its
games [checked]. Every panel moves the same way, and every button sounds like
the same instrument.

**10. Progress is celebrated where it happens.** Some examples:

- A Star Rail Trailblaze level-up comes with rewards [checked].
- Summoners War's monthly check-in pays 28 rewards, and a missed day does not
  restart it [checked].
- AFK Arena returns the player to the world map when a chapter is cleared
  [checked].
- Summoners War's result screen fills each monster's EXP gauge [recalled].

---

## 2. Where we stand, area by area

Our game is not far off, and it is uneven. The chrome (the cream and gold
menus, the painted maps, the painted relics) and the battle's basic juice
(hit-stop, shake, flash, recoil, number pops, dash, swing trails, flipbooks)
already exist. What is missing is the layer the genre adds on top: response,
build-up, celebration, sound, and a set that knows it is a stage. The frames
cited are in `scratchpad/ci241/frames/` (run 241). Line numbers are as of that
run; the camera job is moving some of them.

### The battle

What works: the fixed camera, the plates over the heads, the painted skill
squares, the flipbooks and the dash.

Seven defects found in our own code [ours]:

- **An advantage hit reads as healing.** An advantage hit floats its number in
  #7FE8A0, the same green as a heal (`BattleSceneController.swift`, the
  `.damage` and `.healed` cases).
- **The speed button turns the juice off.** It steps 1 → 2 → 4
  (`BattleView.swift:307`), and at 4 `Juice.skipThreshold` (3.5) turns off
  every freeze, shake and haptic. The choice is also not saved between fights.
- **The shake fights the skill dolly.** Both write the camera's position every
  frame, and the shake eases back to the point where it started
  (`CameraDirector` `shake` against `zoom`).
- **Later waves skate in.** They slide 3 m while playing the combat idle, but
  115 of the 117 families ship a walk clip.
- **The victory is never seen.** The survivors play it facing away from the
  camera, and 1.0 s later a 0.84 black scrim covers them (frames
  `6-battle-c`, `20-victory-a`).
- **The fallen do not leave.** They lie at full opacity until the whole wave is
  cleared.
- **The acting unit is hard to find.** Its marker is a torus 2.8 cm thick that
  reads as a thin purple ellipse (`6-battle-a`). Summoners War uses a large
  glowing circle (the owner's frame).

The hit-stop is set by the hit's WEIGHT alone (`Juice.profile`: 45 ms for a
normal hit, 75 heavy, 90 critical, 150 lethal), so a crit for 40 and a crit for
4,000 freeze for the same 90 ms, and the victim hangs completely still inside
it.

What already floats and must not be proposed again [ours,
`BattleSceneController.swift:950` and `1090–1165`]: a crit in gold with a "!"
at 1.4×, a glancing hit in slate with "glance", RESIST, COUNTER, EXTRA TURN,
"N blocked" for a shield, each status's name as it lands, a passive's name,
and the skill's name over the caster at 0.7× in pale gold. What is missing is
their DESIGN and their sound: they are all the same flat label in different
colours.

### Art direction

Measured on eleven of our battle frames [measured here]:

- **Warm sets:** the arena and the Duat (`8-arena_battle-a`, `6-battle-a`) have
  a median saturation of 0.73–0.76, with 75% of pixels over 0.6. The whole
  frame is orange, so nothing can stand out.
- **Pale sets:** Olympus and the Forum (`29-realm_battle-a`, `-e`) peak at a
  95th percentile of only 0.45–0.51, so the figures are grey on grey.

Three causes:

- Props get a stronger rim light than the figures (0.18 against 0.12).
- The set and the figures share every light.
- No prop glows, so the eye has no path through the frame.

The Norse, Roman and Jade Court props named in the recipes do not exist
(`prop_hall_pillar`, `prop_rune_stone`, `prop_pagoda_lantern` and others). The
fjord and Jötunheim therefore stand on white Greek-style columns with bowls
(`29-realm_battle-c`, `-d`). The Colossus is a sandstone giant against
sandstone statues and a sandstone painting (`18-dungeon_battle-c`), with
nothing to set it apart. `StageBuilder.hangingRocks` is written and never
called.

### Menus

They look premium when they stand still and barely react.

- **Press feedback:** 69 buttons are `.buttonStyle(.plain)` and give no press
  feedback at all. The other 60 shrink to 0.97, with no sound or haptic of
  their own.
- **UI sound:** the whole interface has two sounds, a tap and a confirm. They
  are written by hand into about 99 actions, so they play when the finger
  LIFTS.
- **Wallet and rewards:** the wallet changes in one frame, and nothing flies
  (`14-missions`, `12-shop`, `0-island`). Every reward tile pops with the same
  spring and the same tick, so a Hero relic lands like drachma
  (`20-victory-c`).
- **Badges:** the tab bar has none.
- **Sheets:** five places open as iOS sheets that slide up from the bottom.
- **System dialogs:** thirteen remain, including the battle's gear menu, a
  white iOS action sheet over the fight.
- **Motion:** the UI uses more than twenty different spring settings.

### The summon

- **The grade shows at once.** The charge is coloured by the ELEMENT, and its
  beam width, ring speed and length give the grade away from the first frame.
  `5-reveal-charge` is one flat orange from start to end.
- **A ten-pull is ten single reveals,** about ten taps. Skip also skips any
  5★ still to come. The summary grid is four tiles wide, scrolls on a landscape
  phone, and has never been photographed.
- **The duplicate line can be untrue.** Every duplicate says "one skill
  levelled up" even when every skill is maxed, because the result of
  `ProgressionService.applySkillUp` is thrown away (`SummonService.swift:389`).
- **The figure arrives already idling.** No victory clip plays and nothing
  marks the landing.
- **The temple outshines the god.** In `5-reveal-a`, `-b` and `-awakened` the
  lit columns are brighter than the figure.
- **Most gods arrive in the wrong temple.** The summoning circle has only a
  Greek and an Egyptian set, so every Norse, Roman and Jade Court god arrives in
  the lotus temple.
- **The words float.** The name and stars are loose text over the dusk.
- **The banner art is hidden.** Twelve banner paintings ship, and the room
  shows one only when its own painting is missing (`4-summon`).

### The island and the progress around it

- **Levels pass in silence.** A player level-up refills energy and raises the
  maximum with no word (`CampaignService.settle`). `StageOutcome` does not
  even carry the level.
- **The island hardly moves.** Four figures wander about 50 points each, one at
  a time (`0-island`), although every family now ships a walk clip.
- **Night is a switch.** It is a 45% blue filter switched on at fixed hours.
- **Buildings never grow.** Their tier shows only as diamonds on the name chip,
  and every building opens at level 1.
- **The chapter map never reacts.** Clearing a stage, a boss or a tier plays
  nothing (`13-chapter_map`).
- **The login gift is buried.** It is a small plate inside Missions, and a
  missed day restarts it (`14-missions`).
- **The figure stages ignore a tap.** In the Hall of Ka and the Collection
  stage the figure only turns (`21-collection_stage`).

### Sound and touch

The game has 26 synthesised WAV files, played through `AVAudioPlayer` pools
that can change only the volume. Every realm, the Norse and the Jade Court
included, plays the same two music loops in an Egyptian-sounding mode.

- **Silent events:** heal, shield, every buff and debuff, resist, counter, extra
  turn, revive, death, a wave's arrival and a boss's arrival.
- **Unused files:** `block.wav` and `dodge.wav` ship, and nothing plays them.
- **Victory twice:** the victory sound plays TWICE, from
  `BattleSceneController`'s `.battleEnded` and from `BattleView`
  `beginReckoning`, over battle music that never stops.
- **Summon sound:** the 3★ and 5★ charges are one file at two volumes.
- **Haptics:** only three fixed-strength taps, and no Vibration toggle.

### The areas the six researchers did not study

Found on the art director's pass [ours unless marked]:

- **The unit sheet shows a card, not the god.** `UnitDetailView.identity`
  gives the unit a 150-pt card painting, the chibi bust (`2-detail`,
  `-b`). The serious 3D figure the whole roster was remade into is seen on the
  reveal, the Hall of Ka and the Collection's Stage layout, and nowhere on the
  screen a player opens most.
- **Building a lineup has no motion and no sound.** `TeamPickerView` has no
  animation, transition or sound in its 288 lines. Its rail's lower half is
  empty, and it is the cream page while the briefing that opens it is the
  genre's dark glass over a painting (`42-resonance` beside
  `34-sweep-briefing`). The rail does not show the team's power.
- **A fight opens with a system slide-up.** Every battle is a
  `.fullScreenCover`, so the stage slides up from the bottom of the map like
  an iOS form. The meshes are parsed ahead (`ModelLibrary.warm` in
  `CampaignView`, `ArenaView`, `DraftView`), but no effect is drawn before the
  first cast. The run-221 rule is that a shader compiles the first time
  something is DRAWN with it, so the first ultimate of a session is the frame
  most likely to stall. This is inferred from that rule and has not been
  measured, because nothing measures frames.
- **Frames are not measured.** `Perf` has a main-thread watchdog and load
  timers, and nothing counts frame intervals.
- **The island's figures lag the finger.** The island renders at 30 fps
  (`RenderStage.island`). Its figures are positioned INSIDE the SceneKit scene
  from the painting's frame (`IslandSceneView.Coordinator.update` →
  `layoutFigures`), while the painting under them moves in SwiftUI at the
  display's rate, so during a drag the figures trail the sand by up to 33 ms.
- **120 Hz is unreachable on an iPhone.** `GraphicsSettings.supportsPromotion`
  requires `CADisableMinimumFrameDurationOnPhone`, and neither the pbxproj nor
  `project.yml` sets it. So the Settings page never offers 120, and every
  SwiftUI and Core Animation spring runs at 60 or less on a ProMotion phone
  [checked: Apple's *Optimizing … for ProMotion displays* and developer-forum
  threads say the key is required on iPhone].
- **The battle's controls are small.** The gear, speed and auto controls are
  36 × 36 pt with 6 pt between them (`BattleView.squareControl`), under
  Apple's 44 × 44 minimum [checked].
- **Only one screen size is ever photographed.** CI photographs one iPhone
  15/16-class simulator (`build.yml`). The iOS 17 target admits the iPhone SE
  at 667 × 375 points, and `TARGETED_DEVICE_FAMILY` is "1,2", so the app runs
  on iPads that no frame has ever shown.
- **The arena is a menu with fights in it.** The World Arena has tiers with
  thresholds (`ArenaService.applyResult`, `player.arena.tier`), and crossing
  one is silent. The draft words its own promotion as the title "A new crown"
  (`DraftView.swift:535`). No VS card opens a PvP fight.
- **The first five minutes are menus.** They run key art, then a sign-in
  button, then the island with Athena's plate (`24-launch`, `48-sign_in`,
  `30-guide`). The launch plays the island's loop (`RootView`'s `onAppear`),
  and no spectacle comes before the first menu.
- **Colour alone: checked, and mostly fine.** The matchup marker is a shape
  (up, down or a double arrow) as well as a colour, and W1.2 gives crits a
  word. The one colour-only reading is a plate's element ring, which the
  matchup arrow covers on the player's turn.

---

## 3. The roadmap

Every item from the six areas, with duplicates merged. The fly-to-wallet item
came from two areas, the victory beat from two, haptics from three, the UI
sound vocabulary from two, and the figure-first light from two. The items are
ranked by impact over effort and grouped into waves. **Impact** and **effort**
are 1–5; effort 1 is a few hours and 5 is several days.

Waves 1 to 3 cost nothing. They use art, clips, sprite sheets and props already
in the bundle, sounds made by `tools/sfx.py` and a few CC0 or MIT sample
libraries reachable from here. The paid items are listed separately at the end
with their prices.

**Two rules for building it:**

- **Files the camera job has open.** That job has `BattleSceneController`,
  `BattleSceneView`, `CameraDirector`, `StageBuilder` and `UnitNode` open in the
  working tree today. Every battle item waits for it to commit. The summon,
  menu, island and sound items can start now.
- **Show and check every item.** Each item ends with its CI frame (a tour flag
  is named where one is needed) and goes to the owner as a picture, or as audio
  on an audition page, before he tests it (rule 1 of CLAUDE.md). CI frames are
  still pictures: motion, haptics and sound are judged on the phone.

### Wave 1: the next day's work (the top ten, section 4)

Ten items with the best impact per hour, ties broken by how often a player sees
the thing. Six fix defects the player meets today. With agents working on
separate files, as on the feature day, this is two days.

**The IDs are labels, not ranks.** In every table the ORDER of the rows is the
rank, so an item added on the art director's pass keeps its own number and
stands where it ranks.

| Rank | # | Item | Impact | Effort |
|---|---|---|---|---|
| 1 | W1.1 | Speed ×1/×2/×3, remembered, juice kept at ×3 | 4 | 1 |
| 2 | W1.2 | Damage numbers that read (and the green bug) | 5 | 2 |
| 3 | W1.3 | A hit-stop that grips, and an impact frame | 5 | 2 |
| 4 | W1.8 | One press language, one set of motion curves, and 120 Hz unlocked | 5 | 2 |
| 5 | W1.5 | The summon's rarity ladder, and honest duplicates | 5 | 2 |
| 6 | W1.6 | The player's level-up fanfare | 5 | 2 |
| 7 | W1.4 | The silent fight gets its sounds; victory plays once | 4 | 2 |
| 8 | W1.9 | The turn circle, and the skill word made a banner | 4 | 2 |
| 9 | W1.7 | The end of a fight: final-blow slow motion and victory on the field | 5 | 3 |
| 10 | W1.10 | The unit sheet stands the god up | 5 | 3 |
| — | L1 | Figure-first light, handed to the lighting job (below) | 5 | 2 |

**W1.1 Speed ×1/×2/×3.**
- **What:** the speed control steps ×1 → ×2 → ×3, as Summoners War's does
  [checked], and is remembered between fights (`UserDefaults` key
  `battleSpeed`, a per-device setting, not a save field). At ×3 the juice is
  scaled rather than removed: the freeze is a third with a 20 ms floor, the
  shake is halved, and haptics fire only on a crit, a kill or an ultimate. Skip
  stays the one mode with no feedback.
- **Why:** today a player who taps the control twice loses every bit of impact
  without knowing why.
- **How:**
  - `BattleView.swift:307`: change the step to `speed >= 3 ? 1 : speed + 1`.
  - `BattleViewModel.speed`: its `didSet` writes to `UserDefaults`, and `init`
    reads it back.
  - `Juice.swift`: replace `skipThreshold` with an `isSkipping` flag that
    `skipAnimation` sets, and scale the profile by speed.
  - Grep `PantheonTests/` for `speed` and `skipThreshold`.
- **Cost:** free, a few hours.
- **Risk:** very low. Players who liked ×4 have Skip.

**As built (2026-09-24):** `BattleSpeed` (BattleViewModel.swift) steps ×1 → ×2
→ ×3 → ×1 (`next(after:)`, `top` 3; `settled` rounds and clamps, so an old
stored ×4 reads ×3) and is remembered under the `UserDefaults` key
`battleSpeed`: `BattleViewModel.speed` starts from it and saves every change,
never under `-tour`, so every tour fight starts at ×1 and a step that wants
another speed sets it (the stress fights and the victory step run at
`BattleSpeed.top`). The speed reaches the feel only through
`BattleSceneController.speedMultiplier`. `Juice.skipThreshold` is gone and no
`isSkipping` flag replaced it: Skip is `flush`, which presents no hit at all,
so it needs none to be silent. ×2 halves every freeze and shake as it always
did; ×3 (`Juice.isFast`, over `fastSpeed` 2.5) keeps a third of the freeze over
a 20 ms floor (`scaledFreeze`), half the shake (`shake(for:speed:)`) and the
haptic only for a crit, a kill or an ultimate's hit (`hapticFires`). The heal,
shield, status, resist and SKIPPED sounds stay off at ×3, as W1.4 says. The
gear, speed and auto squares press with `GamePressStyle(.plate)`; they were
silent `.plain` buttons. Tests: the speed rows of `HitFeelTests`, and
`SettingsTests.testTheBattleSpeedStepsOneTwoThreeAndRemembersOnlyThose`.

**W1.2 Damage numbers that read.**
- **Already there, and kept:** a crit is gold with a "!" at 1.4×, a glance is
  slate with "glance", and RESIST floats as a word
  (`BattleSceneController.swift:1090–1140`). This item REDESIGNS those labels;
  it does not add them.
- **What:**
  - **Words over the number:** a small word in Cinzel sits above a bold number
    and replaces the "!" and the "glance" suffix: CRITICAL in orange-gold,
    GLANCING in slate. RESIST and IMMUNE move to the same word style.
  - **Normal hits:** cream, with a thin outline in the attacker's element
    colour.
  - **Crits:** a gold-to-orange gradient at 1.8×, with an overshoot and a
    0.15 s jitter.
  - **Green means healing and nothing else.** An advantage hit gets no colour,
    because the matchup arrow already says it.
  - **Multi-hits:** the early hits of a multi-hit are fainter (0.85×, 80%), and
    a gold TOTAL follows the last hit.
- **Why:** damage-number guides draw crits at 150–200% size, and Ragnarok shows
  faint multi-hits followed by a total [checked]. Today an advantage hit on an
  enemy reads as healing it [ours].
- **How:**
  - `FloatingTextRenderer.image` gets a `word:` line and a gradient fill (the
    text used as a clip, then `drawLinearGradient`).
  - `floatText` takes a `HitWord`.
  - A `pendingTotal[target]` in the `.damage` case is emitted when
    `hitIndex == hitCount - 1`.
  - The word line is 13 pt, over the 11-pt floor.
- **Cost:** free, half a day.
- **Risk:** two-line numbers are taller. Check that they clear the plates on the
  five-a-side `8-arena_battle-aoe-*` frames.
- **The owner's call, not in this item:** a real Crushing Hit (+30% on an
  advantage hit, as in Summoners War [checked]) changes every win-rate curve
  and needs `DamageCalculator`, `BattleEvent`, `balance.py` and the tests
  changed together (about a day more).

**As built (2026-09-24):**
`FloatingTextRenderer.number(_:word:ink:size:opacity:)` draws a number with a
13-pt Cinzel word over it when it has one (`HitWord`: CRITICAL in `#FFB43A`,
GLANCING in `#A6AFBC`, TOTAL) in an ink (`FloatInk`): a normal hit is cream
`#FFF4DE` with a thin rim in the ATTACKER's element colour inside its dark
edge; a crit is a `#FFF1A8` → `#FFC53D` → `#FF7A1F` gradient at 1.8×
(`critScale`, capped at 40 pt) that springs to 1.28 (`critOvershoot`) and
trembles for 0.15 s (`critJitter`), neither under Reduce Motion; a glance is
slate. No hit is green any more: `#7FE8A0` is the heal's alone. A multi-hit's
early hits draw at 0.85× and 80% (`multiHitLook`), and `MultiHitLedger`, keyed
by source AND target, sums each run and floats a gold TOTAL at 1.25× after its
last hit or a kill; a run still open when a turn, a wave or the battle ends is
paid then (`closeOpenTotals`), so a random-target skill whose last hit missed
its victim still earns one. RESIST and IMMUNE (IMMUNE when the victim wears
Immunity) float as carved words at 16 pt (`floatWord`). The two-line labels go
through the same clamps as every float, which read the picture's own size. Not
built: a real Crushing Hit, the owner's call.

**W1.3 A hit-stop that grips, and an impact frame.**
- **What:**
  - **The victim trembles inside the freeze:** 2–3 cm at about 30 Hz along and
    across the hit, dying away by the release, while the attacker holds still.
  - **The freeze grows with the damage, too:** today it is set by weight alone
    (`Juice.profile`, 45–150 ms). It becomes the weight's base plus
    0.10 s × min(1, 3 × damage ÷ max health), capped at 0.22 s. A multi-hit's
    early hits get 60% of it. The post-hit holds (`holdOverride` 0.42–0.55 s
    for heavy, crit and lethal) stay as they are.
  - **The impact frame:** on a crit or a kill only, the first two frames of the
    freeze drop the saturation to 0.25, push contrast and exposure, and burn the
    victim white, then everything snaps back. A kill adds a burst of thin speed
    lines in the element colour.
  - **Limits:** one impact frame per cast at most, and none under Reduce Motion.
- **Why:** Smash's hitlag, where the victim shakes and the freeze scales
  [checked]; the anime impact frame used in the ultimates of Epic Seven, Star
  Rail and Genshin [recalled]. The split between a still attacker and a
  trembling victim is what says "the blade met resistance" rather than "the
  video paused".
- **How:**
  - `Juice.impact` gains `victim:` and `share:`.
  - A main-thread `CADisplayLink` writes the victim's `modelContainer.position`
    while the scene is paused. It touches no `SCNAction` block, and it restores
    the rest position before `isPaused = false`.
  - `CameraDirector.impactFrame(duration: 2/60)` saves the realm's grade values
    and restores them.
  - `UnitNode.flashHit` gains `strength:`.
  - The speed lines are a `Canvas` in `BattleView`, driven by an `impactPulse`
    on the view model.
- **Cost:** free, about a day.
- **Risk:** `Juice.release` must also stop the display link, or a figure could
  be left off its mark. Two of about 120 CI frames may catch the flash, so read
  `framelight.py` knowing that.

**As built (2026-09-24):** `Juice.freeze(for:share:early:speed:)` is the
weight's pause plus 0.10 s × min(1, 3 × damage ÷ max health), capped at 0.22 s
(`longestFreeze`), 60% on a multi-hit's early hits, then scaled by the speed;
`Juice.impact` takes `share:`, `early:`, `ultimate:`, `freezeFor:`, `shakes:`
and `victim:`. The victim trembles inside the freeze (`Tremor`: 0.013 of its
height held to 2–10 cm, so 2.5 cm on a 1.9-m figure, at 30 Hz across and a
little along the blow, dying by the release; `modelContainer`'s x and z only,
put back on its rest position before `isPaused` goes false; not in a freeze
under 30 ms, never under Reduce Motion). The plan's `CADisplayLink` is a
`FrameTicker`, a 120-Hz `Timer` in the main run loop's common modes whose
target is a `WeakTickTarget` holding only the step, because swiftcheck's
`--types` list of the frameworks' names has no `CADisplayLink`;
`Juice.stopTremor` ends it on every new impact, on the release, and in
`Juice.release` (every skip, forfeit and new run). The impact frame is
`CameraDirector.impactFrame(duration: 2/60)`: saturation 0.25, contrast +0.35
and exposure +0.3 on the realm's grade, which the director reads when it is
made and puts back exactly (a generation guard; never under Reduce Motion or
over a draining field), with the victim burnt white for two frames
(`UnitNode.flashHit(strength: 1.4)`). A kill adds sixteen speed lines and a
core in the striker's colour for about a quarter of a second, drawn in the
plate overlay's SpriteKit burst layer rather than a SwiftUI `Canvas`, because
that overlay already projects every unit each frame. One impact frame per cast,
a counter counting as a cast of its own, and the FINAL blow owns it: a crit or
a kill earlier in a cast that goes on to end its side leaves the frame to the
final blow (`finalBlowFollows`, read off the queue). The final blow used to
punch past the limit, so an area ultimate that crit and then wiped a wave
punched twice inside a second (review, the same day).

**W1.4 The silent fight gets its sounds.**
- **What:** about eighteen short sounds, one per silent event:
  - **heal:** a harp glissando upward.
  - **shield:** a crystal ring.
  - **buff and debuff:** a rising chime and a falling dissonant pair.
  - **stun, freeze, burn, provoke and bomb:** a sound each.
  - **resist and glancing hits:** `block.wav`, and `dodge.wav` under the hit.
    Both already ship.
  - **counter:** a steel sting.
  - **extra turn:** a bright three-note motif; it must feel like a reward.
  - **revive:** a choir swell.
  - **death:** a fall and a soul whoosh.
  - **a wave's arrival:** a horn call per realm.
  - **a boss's arrival:** boom, roar and cymbal.
  - **the player's turn:** one soft chime.

  Victory plays once: `.battleEnded` stops the battle music, and the reckoning
  plays the fanfare in time with its ribbon.
- **Why:** principle 6. Premium turns can be followed by ear [recalled].
- **How:**
  - One `AudioLibrary.shared.play` beside each existing `floatText` or VFX call
    in `BattleSceneController.handle`. Statuses map through a `switch` on
    `StatusKind`, so swiftcheck catches a missing case.
  - The sounds are built in `tools/sfx.py` (new `build_status()` and
    `build_flow()`), plus harp, bell-tree, glockenspiel and gong one-shots from
    VSCO-2-CE (CC0, licence read). A sparse clone of it was tested from here.
  - Status sounds are skipped at ×3, and the per-turn chime is capped at 0.35
    volume.
  - The sounds ship with the first **audition page**: a private artifact with
    a player for every new sound, its trigger and its licence. That is how
    rule 1 is met for sound.
- **Cost:** free, about a day.
- **Risk:** noise on an auto farm at ×3. Hence the skips and caps.

**W1.5 The summon's rarity ladder, and honest duplicates.**
- **What:**
  - **Every charge opens the same:** cool blue-white light, a narrow beam,
    slow rings, and always 1.25 s (1.4 s for a 5★).
  - **It climbs in steps:** at 35% a 4★ or better turns violet (the beam
    widens, the rings speed up, a sting and a haptic). At 70% a 5★ breaks into
    gold with lightning around the beam (the nat-5 tell). A Light & Dark result
    then splits white-gold or violet-black.
  - **The element moves** to the rings' glyphs and the pool of light on the
    floor.
  - **Duplicates tell the truth:** the result carries which skill levelled and
    to what level, shown as that skill's icon and "Lv 3 → 4". A maxed duplicate
    says "Skills maxed — feed to the Regalia". A new unit shows its Codex page
    and the divinity it will pay.
- **Why:** Genshin's blue or purple to gold [checked]; Summoners War's
  deliberate 4-or-5 suspense and its lightning tell [checked]. Today the grade
  shows on the first frame and a duplicate can claim something untrue [ours].
- **How:**
  - `SummonRevealView`: a pure `rung(stars:progress:)` feeds the beam, flare
    and motes in `chargeLook` from `Rarity(stars:).glow`, stepping by
    smoothstep over 0.15 s. It stays a pure function of the clock, as the
    comment requires.
  - The lightning is `vfx_lightning_sheet.png` (already in the bundle) cut into
    16 frames once.
  - `SummonResult` gains `skillUp` and `codexDivinity` with defaults, so the
    three other builders (`ShrineService`, and `MileageService` twice) still
    compile. They are filled at `SummonService.swift:389`.
  - The CI hold gets a fraction, `-tour-reveal-hold charge:0.8`, so the gold
    step is photographed.
- **Cost:** free, about a day and a half.
- **Risk:** the violet step must only ever mean a real 4★ or better; never fake
  one. An additive lightning layer can clip, so check it with `framelight.py`.

**W1.6 The player's level-up fanfare.**
- **What:** a LEVEL UP beat between the reckoning and the chest. Big carved-gold
  numerals ("LEVEL 8") spring in over light shafts, followed by:
  - "Energy refilled 84/84",
  - "Max energy +2",
  - "+25 Divinity",
  - anything that level unlocks, such as a decoration.

  On the next island visit the header's level ring bursts once and its number
  rolls over.
- **Why:** Star Rail's Trailblaze level-up [checked]; Summoners War's level-up
  refill [checked in part]. Today the refill happens with no word at all [ours].
- **How:**
  - `StageOutcome` gains `playerLevelsGained` and `newPlayerLevel`, with
    defaults.
  - `BattleSummary` gains `levelUp`.
  - A `Phase.levelUp` in `BattleView`, drawn with `.keyframeAnimator`
    (the deployment target is iOS 17).
  - A non-saved `pendingLevelCelebration` on `GameStore`.
  - `level_up.wav` from `sfx.py`.
  - The tour seeds one on step 20 (`20-victory-levelup`).
  - Grep `PantheonTests/` for `StageOutcome(`.
- **Cost:** free, half a day.
- **Risk:** an auto-repeat of twenty runs must show one combined beat at the
  end, not twenty.

**As built (2026-09-24):** `StageOutcome.playerLevelsGained` and
`newPlayerLevel` (defaulted); the settle's per-level numbers named
(`CampaignService.maxEnergyPerLevel` 2, `divinityPerLevel` 25, the values
unchanged); and `BattleSummary.levelUp`, a `PlayerLevelUp` (the levels, the bar
the settle left, `maxEnergyGained`, `divinity`, and `LevelUnlock.between`: a
building that opens, a decoration the chisel now sells, a building's next
tier). `BattleResultView`'s `Phase.levelUp` stands between the reckoning, whose
line then reads TAP TO CONTINUE, and the chest: LEVEL N in carved gold
springing in on the `.levelUp` fanfare's chord at 0.3 s (`LevelNumeralFrame`,
`.keyframeAnimator`) over `LightShafts`, then the chips — Energy refilled N/N,
Max energy +N, +25 Divinity, and at most three unlocks with the rest counted on
the last. A tap in its first second is ignored. An auto-repeat banks every
run's levels in `RepeatSession` and shows ONE beat at its end.
`GameStore.pendingLevelCelebration` (a `LevelCelebration`, never saved) is set
by `finishCampaignBattle` and `sweep`, merged across clears and taken once
(`takeLevelCelebration`): the island's header ring swells, a ring of gold
bursts out of it and Lv. rolls from the old level to the new (`.numericText`)
once the island is both the selected tab and on screen. Unlike the plan, the
tour photographs a REAL win's level-up (`-tour-victory field`: Duat 1-1 on auto
at ×3, the demigod and the team's leader seeded one experience short;
`20-victory-levelup` on `[TourCue] levelup`) rather than a seeded summary. Left
to the owner: a level-up sets the energy TO the new bar, the rule before this,
so a player holding more than the bar loses the excess while the chip reads
N/N. Tests: `LevelUpTests` (four, in ProgressionTests.swift).

**W1.7 The end of a fight: final-blow slow motion, and victory on the field.**
- **What:**
  - **The final blow:** when a blow ends a wave or the fight, a 0.2 s freeze and
    impact frame, then time runs at 0.3 for 0.6 s while the camera eases toward
    the victim along the home line of sight (the floor never turns), then time
    ramps back to 1 with a low "whoomp".
  - **Victory on the field:** for 2.4 s before the reckoning, the HUD fades,
    the survivors TURN TO FACE THE CAMERA and play their victory clips, and the
    camera frames the team.
  - **EXP on the plates:** each plate swaps health for a gold EXP bar that
    fills, with LEVEL UP rising over each unit that levelled.
  - **The stamp:** VICTORY is stamped over the live scene and the three stars
    slam in one by one.
  - **The reckoning:** it then slides in over a 0.55 scrim instead of 0.84, so
    the team stays visible behind it.
  - **Defeat:** the colour drains to saturation 0.15 and DEFEAT sits in wine
    over the grey field.
- **Why:** Summoners War shows VICTORY over the live field with the monsters
  posing and their EXP filling [recalled]. *Juice it or lose it* says to dwell
  on kills [checked]. 115 families ship a victory clip that nobody has ever
  seen from the front [ours].
- **How:**
  - `BattleSceneController`:
    - `slowMotion(to:for:easeBack:)` tweens the existing `speedMultiplier`
      from a display link; `beat()` already divides every timer by it.
    - In `.battleEnded`, a yaw-only `look(at:)` toward the camera (never
      `atan2`, per CLAUDE.md), then `play(.victory)`.
    - `celebrate(experience:)`.
  - `CameraDirector`: `frameTeam()` through `zoom`.
  - `BattleView`: `Phase.triumph` and a `VictoryStamp` view, with the
    reckoning's `summary` held back 2.2 s.
  - `BattleSummary` carries each unit's experience before and after.
  - The tour photographs `20-victory-0` (the stamp over the field) and
    `20-victory-triumph`.
- **Cost:** free, about two days.
- **Risk:**
  - The team's FRONT shows in battle for the first time, so read the frame.
  - Until the motion roll-out lands, every family poses with the same preset
    412 (`MOTION.md`). The beat is still worth having, and it gets better with
    each family's own pose.
  - An auto-repeat plays it on the last run only.
  - Check that `playbackSpeed` re-times a clip that is already running.

**As built (2026-09-24):** The final blow (`endsItsSide`: a kill that leaves
its side empty) starts the victim's fall on the blow (`beginFinalFall`), holds
0.2 s (`Juice.finalBlowFreeze`, ÷ the speed) with the impact frame, then runs
time at 0.3 for 0.6 s (0.06 s in, 0.25 s out, all ÷ the speed). The slow motion
is its own `timeScale`, multiplied into the player's speed as `pace`, not a
tween of `speedMultiplier`, so the player's pick is never written over; every
running clip follows it (`UnitNode.playbackSpeed` re-times an animation player
and the counted clock that ends a one-shot, `ClipPace`), every particle
system's `speedFactor` slows with it, `.whoosh` plays at 0.9 as time returns,
and the camera eases toward the victim along the home line of sight and back
(`easeToward`, the victim at most 42% of the frame). The queue holds through
all of it. The triumph is `BattleSceneController.celebrate(experience:)`,
called once by `BattleView` on the last run's win: the slow motion ended, every
survivor steps onto its mark, turns to the lens with a yaw-only
`look(at:up:localFront:)` in one `SCNTransaction` (0.45 s) and plays its
victory clip at ×1 whatever the fight's speed (`triumphPosePace`: at ×3 the
2.0-s pose had played in two thirds of a second, review), then its standing
idle. `frameTeam` brings the camera in along the home line of sight over 0.9 s
and holds, the team's chests 0.42 of the half-frame under the centre (0.22 put
every LEVEL UP under the VICTORY band, review). Each plate's bars give way to a
gold EXP bar filling from `ExperienceGain.from` to `.to`, keyed by COMBATANT id
and measured by `BattleViewModel.experienceGains()` from the unit as THIS run
began (taken again for every run of a repeat, since the badge shows the run's
own level; review); a unit that levelled fills to the end, bumps its badge,
flashes, and LEVEL UP rises out of the plate into its place over the track and
stays, breathing. `BattleView`'s `FieldBeat` goes fighting → triumph or fallen
→ reckoning. The HUD fades; a win stamps `VictoryStamp` (VICTORY slams onto a
gold-ruled band, a ring goes out, the stars slam in an arc) and holds
`triumphDuration`, 2.4 s; a loss or a draw calls `drainColour(duration: 0.8)` —
saturation to 0.15 (`drainedSaturation`) as the grade's own action, which
`stopMoves` leaves alone — under `DefeatStamp` (wine; DRAW in marble) for 2.0
s; a tap after 1.2 s hurries on. The reckoning slides in over 0.55 (0.84
before), its stars already lit, and the level-up and the chest deepen it to
0.84. A forfeit stops the fight where it stands: the waiting turn withdrawn, no
other handed out, and the turn in playback halted
(`BattleSceneController.halt`; review). Unlike the plan, the team poses in
`celebrate`, not at `.battleEnded` (the enemies still pose there on a loss, at
the fight's speed), and the tour adds `20-victory-defeat`. Under the tour the
pose plays at a quarter of its pace (`tourPosePace`), because a simulator
screenshot lands two to three seconds after it is asked for; the scene's own
lab, `-tour-triumph win|loss`, is not photographed.

**W1.8 One press language, and one set of motion curves.**
- **What:**
  - **Seven named curves in `Theme.swift`** (`Motion.tap`, `select`, `pop`,
    `panel`, `exit`, `celebrate`, `ambient`), with `Motion.respecting(_:)` for
    Reduce Motion.
  - **One `GamePressStyle` in four kinds:**
    - `.primary`: gold plates sink to 0.94 with the gloss dimming, then spring
      to 1.04 and settle on release.
    - `.plate`: cards and tiles, 0.96 then 1.02.
    - `.medallion`: tab doors, the back button and header doors, 0.9 with the
      rim brightening.
    - `.quiet`: list rows, brightness only.
  - **Sound and haptic on touch-down**, so the thumb, the ear and the eye get
    the press at the same moment. The "done" sound stays in the action.
  - **120 Hz unlocked (one line, and a defect).** Add
    `INFOPLIST_KEY_CADisableMinimumFrameDurationOnPhone = YES` to both app
    configurations in `Pantheon.xcodeproj/project.pbxproj` and to
    `project.yml`. Without the key an iPhone never draws a custom animation
    faster than 60 Hz, and `GraphicsSettings.supportsPromotion` hides the 120
    choice that the feature day built. The battle and the reveal stay at 60
    unless the player picks 120 (`FrameRateChoice.standard` is the default),
    and the island stays at 30, so battery use changes only where the player
    asks for it. Every curve in this item is then drawn at the phone's own
    rate.
- **Why:** Swink's polish, the 100–200 ms rule, and one design system
  (principles 2 and 9) [checked]. Apple requires the key for rates above
  60 Hz on iPhone [checked]. Today 69 buttons give no feedback, the UI uses
  more than twenty different springs, and a Pro iPhone draws them at half its
  rate [ours].
- **How:**
  - `Components.swift`: `GamePressStyle` reads `isPressed` through `onChange`,
    and makes the overshoot with `keyframeAnimator`. `PlateButtonStyle` becomes
    a typealias, so its 60 call sites still compile.
  - Move the 69 `.plain` buttons over, and delete their hand-written
    `.uiTap`/haptic lines.
  - Map the roughly 40 `.spring(response:` literals in `Pantheon/UI` to the
    tokens. The battle and reveal cinematics keep their own numbers.
  - A swiftcheck rule flags new spring literals in the chrome.
- **Cost:** free, about a day and a half.
- **Risk:**
  - Double sounds wherever an action still plays `.uiTap`. Grep for them.
  - A scrolling row reports a press on a drag, so use `.quiet` there.

**W1.9 The turn circle and the skill banner, from the owner's own frame.**
- **What:**
  - **The turn circle:** the thin torus under the acting unit becomes a flat
    rune disc 0.95 × the unit's width, in the element colour. It turns slowly,
    has a soft glow under it, and pops in when the turn begins.
  - **The skill banner:** over the caster, the skill's painted ICON in a gold
    frame beside its name at 20 pt (Summoners War's "Team Up" banner, as in the
    owner's frame). It REPLACES the plain name that floats today at 0.7× in
    pale gold (`BattleSceneController.swift:950`, the `.skillCast` case). It
    is not a second label.
  - **Arming a skill:** a selection tick and a gold ring pulse on the square.
  - **Tapping an enemy:** stamps an element-tinted reticle on it.
  - **Cooldowns:** a skill coming off cooldown gets a gloss sweep and a chime.
- **Why:** both of the owner's frames show the big green circle and the
  icon-and-name banner [checked]. Ours is a thin ellipse that reads as a target
  marker (`6-battle-a`) [ours].
- **How:**
  - `UnitNode`: the `selectionRing` becomes an `SCNPlane` lying flat, with the
    `castRing` picture, `writesToDepthBuffer false`; `setHighlighted` runs the
    pop.
  - `FloatingTextRenderer.imageWithIcon` draws `SkillArt`'s icon.
  - The reticle is `UnitPlateOverlay.stampReticle(at:)`.
  - The cooldown glint is diffed in `BattleView`.
- **Cost:** free, a day.
- **Risk:**
  - On the pale sets an additive disc can blow the floor, so hold it at 60%
    brightness there.
  - The banner is wider than the name, so the float clamp must include it.
  - Check `6-battle` and `29-realm_battle`.

**As built (2026-09-24):** The torus is the turn disc
(`UnitNode.makeTurnDisc`): `StageBuilder.runeRing` in the element's colour,
additive and writing no depth, over a soft pool half as wide again, 0.6 of the
unit's height across (about 0.95 of its width). It pops in from 0.55 as the
turn begins, breathes between 72% and 100% of `turnDiscPeak` (0.9; 0.54 on
Olympus, the Aegean cliffs and the Forum, `StageBuilder.isPaleSet`), and fades
on a death and at the triumph; under Reduce Motion it fades in at its size. The
skill banner (`floatBanner`, `FloatingTextRenderer.banner`) is the square's own
painted icon, resolved over the kit exactly as the HUD resolves it
(`SkillArt.keys`), in a gold frame beside the name in 20-pt Cinzel, held 0.45
s; it replaces the name float for every cast but an ultimate, whose cut-in
already names it. Arming a skill plays `.uiTap`, a light haptic and a gold ring
out of the square (`SkillArmRing`); a skill ready again gets a gloss
(`SkillGloss`) and a `.starTick` 0.3 s after the squares appear, found by
diffing each unit's cooling slots from its last turn (`noteCooldowns`; nothing
plays on auto). A tap on an enemy stamps a 60-pt reticle in the acting unit's
element colour (`stampReticle(on:in:)` → `UnitPlateOverlay.stampReticle`),
landing from 1.7× and 45°, or fading in alone under Reduce Motion.

**W1.10 The unit sheet stands the god up.**
- **What:**
  - **The figure takes the card's place:** the left column's 150-pt card
    becomes the unit's own 3D figure. It stands on a small rune plinth in its
    resting idle, turned three-quarters toward the relic ring, with a drag to
    turn it (the Collection stage's gesture). An awakened unit stands in its
    awakened mesh with that mesh's clips
    (`ModelLibrary.clipAsset(for:awakened:)`).
  - **The column is dark glass:** the figure stands in a dark glass well with
    the summoning hall's floor blurred behind it, because a figure on cream
    reads as a cut-out. This follows the premium pass's rule: cream for chrome,
    dark glass over art. The ring, the stats and the skills stay cream.
  - **The card is one tap away:** it shrinks to a 44-pt thumbnail in the well's
    top-left corner, and a tap on it flips the well to the full card painting
    and back.
  - **What stays:** the level bar, the power and the Power up / Evolve / Awaken
    buttons stay under the figure.
  - **The figure answers:** with W2.15 it answers a tap, and it breathes the
    altar's flare once when the player returns from the Hall of Ka after a
    level, evolution or awakening.
- **Why:**
  - Every rigged family was remade in the serious style between 2026-09-18
    and 09-23, the owner's largest spend on the game. The screen a player opens
    most still shows the chibi bust card (`2-detail`, `2-detail-b`) [ours].
  - Summoners War's monster screen shows the monster's model, and Genshin's
    and Star Rail's character screens are built around the full 3D figure
    [recalled].
  - This is the one screen where the "cheap copy" the owner named is a matter
    of what is SHOWN, not how it is drawn.
- **How:**
  - `UnitDetailView.identity(_:height:)` hosts the figure stage from
    `CollectionStageView` (`CollectionView.swift:1004`). Give that view a
    `Framing` value (the centre line, the feet and the fill: 0.5, 0.86 and
    0.78 for a narrow column), with today's 0.66, 0.78 and 0.70 as its
    default so the Collection is unchanged.
  - `FigureStageLighting` and `restrictShadows` come with the stage.
  - The flip is a `rotation3DEffect` between the stage and a `PortraitPainting`.
  - The tour's `2-detail` and `2-detail-b` frames become the check: a 5★ Zeus
    and an awakened Anubis.
- **Cost:** free, a day.
- **Risk:**
  - Memory: one more figure lives while the sheet is open. It goes through
    `ModelLibrary`'s bounded cache (commit 1b1bf74), and the stage's
    `dismantleUIView` must drop its scene.
  - The idle must start the `startLoop` way: the figure goes into the live
    scene first (the Hall of Ka's bind-pose lesson).
  - Opened over the Collection's Stage layout, the same figure is drawn twice
    for a moment. That is harmless, because the parse is shared.

**L1 Figure-first light: handed to the lighting job.** It was W1.10. It is
lighting, and a lighting job is running now, so it is that job's to take or
leave, and it does not hold a top-ten place here. If that job has not split
the lights when it commits, build it next. W2.9 (the ultimate spotlight) and
W3.27 (the boss pocket) are built on it. Its summon-reveal half
(`SummonRevealView`) is not a battle file, so it can start now, beside W1.5.
- **What:**
  - **Separate lights:** the figures and the set stop sharing every light.
    Units get light category 2 and the set category 4. The set keeps the
    realm-tinted fill and ambient; the figures get their own neutral fill (80%
    toward white). The key light and the shadows stay one light.
  - **Set saturation:** the set's materials drop to 0.80 saturation and the
    figures stay at 1.0.
  - **Prop rim:** it goes from 0.18 to 0.06, under the figures' 0.12.
  - **The summon reveal the same way:** the figure gets the key, fill and tinted
    rim, and the temple its own key at 0.6 of it. The braziers reach 3 m instead
    of 6, and after the flash the set dims a further third of a stop, like a
    theatre darkening its house.
- **Why:** principle 1, as measured on the owner's frames. The same finding
  came from both the art and the summon research: our warm sets are saturated
  all over, and the reveal's columns outshine the god (`5-reveal-a`,
  `-awakened`) [measured].
- **How:**
  - Set `categoryBitMask` on every node with `enumerateHierarchy`. It is NOT
    inherited, so this includes clones swapped in later (`UnitNode.init`,
    `restartIdle`).
  - `BattleSceneController.buildLighting`: split the lights into a set pair and
    a figure pair.
  - `MaterialTuner`: a `setSaturation` value, and a short surface modifier on
    the floors, the same luma mix as the figures'.
  - `SummonRevealView.makeUIView`: the same masks for the reveal.
  - A lab flag, `-tour-layers off`, photographs the old rig beside the new.
- **Cost:** free, half a day to a day.
- **Risk:**
  - The braziers must pick the set, so the fire stops warming the figures.
    That is right for readability, and some warmth is lost.
  - Check that the image-based light still reaches the figure.
  - Reversible with one flag.

**Timing note for L1.** The lighting job is doing the clean lighting now. If
it has already split the lights, L1 is done and W2.9 can start. If it has not,
L1 is the first battle item after that job commits.

**As built (2026-09-24), the battle's half:** the figures on light category 2
(`StageBuilder.figureCategory`; `UnitNode.markFigure` in `init`, `restartIdle`,
and after a boss's lamp is hung, since a category is not inherited) and the set
on 4 (`StageBuilder.separateBattleSet` at the end of `buildBattleStage`, and on
the boss's breach, which is built later). The set's fill and ambient light the
set alone (`setLights` 4); the figures get a fill and an ambient of their own
at the same strength and from the same side, 80% of the way to white
(`figureFillWhite`; `figureLights` 2 | 1, so anything added to the field
unmarked is lit as a figure is); the key stays one light over both and casts
the set's shadows; the braziers light the set; the boss's warm spot is a figure
light and no longer reaches the stone round the breach; an effect's own light
keeps every category. A prop's materials are copied before they are changed
(`MaterialTuner.tuneSetProp`: paint at 0.80, `setSaturation`, and a rim of
0.06, `setPropRim`), so `propCache` is untouched; every other lit set material
takes a short surface modifier to 0.80 (`calmSet`) — except the battle slab's
top, whose painted tile and tint are already calmed to 0.5 where it is built
(`arenaFloorSaturation`; `calmedAtBuild`): the two passes together had left the
stone at 0.4 (review, the same day), and a calmer floor is a change to that one
number. `-tour-layers off` builds the shared rig of before, photographed as
`6-battle-layers-off` beside `6-battle-a`. To confirm on the frames: the
image-based light (`scene.lightingEnvironment`) has no mask and should still
reach the figures; the set's modifier adds shader variants, so a battle's first
frame may compile a little longer.

### Wave 2: the next week, still free

Larger builds and the items that depend on Wave 1, in ranked order (the row order is the rank; W2.24–W2.28 came from the art director's pass).

| # | Item | Impact | Effort |
|---|---|---|---|
| W2.1 | The ultimate cut-in as a full splash, the world held | 5 | 3 |
| W2.2 | The reward box by rarity, with its own sounds | 5 | 3 |
| W2.3 | The ten-pull as one ceremony, and a summary that fits | 5 | 4 |
| W2.4 | The summoned figure's entrance | 5 | 3 |
| W2.5 | The chapter map plays the clear | 5 | 3 |
| W2.6 | Layered hits with recorded CC0 transients | 5 | 3 |
| W2.7 | Summon sound that climbs with the grade | 5 | 3 |
| W2.24 | The way into a fight: a stage card, no slide-up, effects drawn before the first cast | 4 | 2 |
| W2.26 | Frame pacing measured, and the island smooth under the finger | 4 | 2 |
| W2.8 | Deaths that leave the field | 4 | 2 |
| W2.9 | The ultimate spotlight: the set dims, the caster stays lit | 4 | 2 |
| W2.10 | Waves walk in, and a WAVE stamp | 4 | 2 |
| W2.11 | The boss entrance | 4 | 2 |
| W2.25 | The lineup built by hand: cards that fly, a crown, resonance that lights, power that rolls | 4 | 2 |
| W2.12 | Missions: Claim All, ready rows first, a stamped DONE | 4 | 2 |
| W2.13 | The carved name card on the reveal | 4 | 2 |
| W2.14 | One continuous shot from the summon button to the beam | 4 | 2 |
| W2.15 | The figure stages answer a touch | 4 | 2 |
| W2.16 | A colour grade per realm, and a saturation check in CI | 4 | 2 |
| W2.17 | Carvings that glow in the realm's accent colour | 4 | 2 |
| W2.18 | The trauma camera shake on a rig | 4 | 2 |
| W2.19 | A haptic vocabulary on Core Haptics, with a Vibration toggle | 4 | 3 |
| W2.20 | A UI sound vocabulary inside the shared components | 4 | 3 |
| W2.27 | Readable and touchable on the smallest phone (and seen on an iPad) | 3 | 1 |
| W2.21 | Numbers that roll, and deltas that rise | 3 | 2 |
| W2.22 | Status effects and attack-bar pushes that land | 3 | 2 |
| W2.28 | The arena as a contest: a VS card and a promotion ceremony | 3 | 2 |
| W2.23 | Skip that never swallows a 5★ | 3 | 1 |

**W2.1 The ultimate cut-in as a full splash.**
- **What:** a 0.9 s splash (0.45 s at ×2, and a 0.3 s name flash at ×3):
  1. The scene pauses and the field darkens 55%.
  2. A diagonal band 60% of the screen tall sweeps in at 12°. It carries the
     caster's CARD painting at full band height (the `PortraitPainting` bust
     crop), speed lines in the element colour, and the skill's name carved in
     gold at 34 pt.
  3. A sting and a heavy haptic play as the name lands.
  4. A two-frame flash, then the wind-up plays in full.

  A setting, "Ultimate splash: Always / First each fight / Off", covers auto
  farming.
- **Why:** Epic Seven, Star Rail and Raid let the ultimate own the screen for a
  second [recalled]. Today the best art in the game, the 1,024 px card, is shown
  at 64 points while the fight keeps playing under the band [ours].
- **How:**
  - `BattleSceneController.holdForCutIn(_:)` pauses the scene and adds to
    `holdOverride`. The charge and cast ring start after it, strictly before the
    clip starts (the `contactFraction` table stays true).
  - Rebuild `cutInBanner` with a parallelogram mask and a `Canvas`.
  - The tour flag `-tour-cutin` photographs it mid-hold.
- **Cost:** free, a day.
- **Risk:** the timing of the playback queue; hence pause strictly before the
  clip.

**W2.2 The reward box by rarity, with its own sounds.**
- **What:**
  - **Tiers:** each spoil gets a tier (plain, rare, epic, legend) from its
    quality, grade or stars, and the shelf lands plain first and the best LAST.
  - **Rare:** a blue under-glow.
  - **Epic:** a purple back-light and a short pause before it.
  - **Legend:** the row stops 0.35 s, a gold column of light stands behind the
    socket, rays turn, the tile drops from 1.4 with a small landing shake, and
    a rising three-note sound plays with a heavy haptic.
  - **The chest:** it rattles three times, rising, then the lid creaks and
    thuds and the beam shimmers.
  - **The tiles:** each clinks one note higher up a pentatonic scale, so a big
    haul plays a melody.
  - **The backdrop:** the panel stands over a blurred still of the fight
    instead of black (`20-victory-b`).
  - **The relic power-up:** a short drum roll, then an anvil ring or a dull
    crack.
- **Why:** Raid's shard colours [checked]; the Genshin and Star Rail colour
  tells [recalled]. Today a Hero relic lands with the same beat as drachma
  (`20-victory-c`) [ours].
- **How:**
  - `RewardTier` and `RewardTile.tier` in `Components.swift`.
  - `SpoilsPanel.grid` sorts by tier, and `openChest` gives each tile its own
    delay.
  - A `RewardTierAura` view built from `AngularGradient` and `.plusLighter`.
  - A `SCNView.snapshot()` taken when the result arrives.
  - `sfx.py` builds the sounds from the VSCO sources.
  - The tour flag `-tour-spoils legend`.
- **Cost:** free, two days.
- **Risk:**
  - A tap must still land everything at once (`finishOpeningNow`).
  - Keep the drum roll off bulk power-ups.

**W2.3 The ten-pull as one ceremony.**
- **What:**
  1. One charge on the W1.5 ladder, climbing to the BEST grade in the ten.
  2. The flash opens onto a 5 × 2 board of face-down cards that flip left to
     right, 90 ms apart.
  3. A 4★, a 5★ or a NEW unit lands with a rim flare, and the board steps aside
     for that unit's full 3D reveal.
  4. It ends on a summary that always fits a phone: ten 96-pt `UnitCard`s, a
     line like "1 ★★★★★ · 2 ★★★★ · 3 new", the new pity count, and "Summon ×10
     again".

  A tap on a card replays that unit's reveal.
- **Why:** Summoners War's 10× exists because single reveals were slow
  [checked]; Genshin's single meteor and quick cards [recalled]. Today it is ten
  taps, and the summary scrolls and is never photographed [ours].
- **How:**
  - A new `Pantheon/UI/Summon/SummonBoard.swift`.
  - A `Phase` enum on `SummonRevealView`, driven by its `sequence` counter.
  - Mount the stage only for the featured results, and `ModelLibrary.warm` them
    all the moment the board shows.
  - `onSummonAgain` passed from `SummonView`.
  - A CI step `4-summon-ten` (`-tour-reveal ten`). The stress loop
    (`-tour-stress summon`) must learn the board path.
- **Cost:** free, two to three days. An optional painted card back is 6 credits.
- **Risk:** "Summon again" makes spending faster. It spends in-game scrolls only;
  read it against `Docs/STORE.md`'s review notes.

**W2.4 The summoned figure's entrance.**
- **What:**
  1. At the flash the scene holds for 70 ms (110 ms for a 5★).
  2. The figure plays its **victory** clip once, then settles into its idle.
  3. The camera kicks back 4% and springs home.
  4. The shockwave flipbook lies flat under its feet, and a 5★ gets the
     sunburst behind it.
  5. The name slams on the clip's high point, not on a timer.
- **Why:** the genre never reveals a unit idling [recalled], and Vlambeer pauses
  on a big moment [checked]. 115 victory clips go unused in the reveal [ours].
- **How:**
  - In `SummonStageView.show`, start the clip through an `SCNAnimationPlayer`
    `play()` (the figure is already in the live scene).
  - Warm the clip and the flipbook in `makeUIView` so no shader compiles at the
    flash (the run-221 lesson).
  - A small `revealApex` table.
  - `settle` starts after the clip.
- **Cost:** free, one to two days.
- **Risk:**
  - Some victory clips step off the dais or turn away; keep a per-family deny
    list.
  - With every family on preset 412 until the motion roll-out lands, the
    entrance looks the same for all of them.

**W2.5 The chapter map plays the clear.**
- **What:** on returning to the map after a first clear or a new best:
  1. The medallion flips from bronze to gold and its stars stamp in one by one.
  2. The leader's face hops along the road to the next medallion.
  3. The next lock breaks into four shards.
  4. A chest that became claimable jumps with a beam.

  A boss's first clear crosses the map with a carved **CHAPTER CONQUERED**
  ribbon, the Hard chip's lock falls off, and on the world road the next city
  ignites.
- **Why:** AFK Arena's return to the world map on a chapter clear [checked];
  Summoners War's stamped stars [recalled]. Today the map is the same before
  and after (`13-chapter_map`) [ours].
- **How:**
  - A non-saved `GameStore.lastClear`, set where a stage settles, so a swept run
    and a fought run share it.
  - A `phaseAnimator` in `ChapterMapView`.
  - The face follows the node line, not the painted road.
  - The tour flag `-tour-map-clear`.
- **Cost:** free, a day.
- **Risk:** it must wait for the victory to finish dismissing, and repeats must
  not replay it.

**W2.6 Layered hits.**
- **What:** four variants of every hit tier. Each variant is:
  - a recorded transient (Kenney's metal, plate and punch impacts, and VSCO
    anvil hits for crits; all CC0),
  - our synthesised body,
  - a tail.

  Beyond that:
  - **Weapon:** blade adds a high "shing"; blunt goes lower.
  - **Crit:** a short reverse swell into contact and a metallic ring.
  - **Lethal:** a sub-drop.
  - **Matchup:** advantage is 2 dB brighter; disadvantage is muffled.
  - **Ultimates:** each gets a riser in its element instead of the generic
    whoosh.
- **Why:** the "crunch" of premium hits is recorded material [recalled]. Today
  every normal hit in the game is the same waveform [ours].
- **How:**
  - `build_layered_hits()` in `sfx.py`, with its sources kept in
    `Art/Audio/sources/` beside a `LICENSES.md`.
  - `Juice.impact` gains `matchup:`.
- **Cost:** free, a day.
- **Risk:** recorded and synthesised material can sound like two sources. One
  shared `space()`/`finish()` chain fixes that. The Kenney files come from a
  third party's GitHub mirror, so re-read each pack's `License.txt`.

**W2.7 Summon sound that climbs with the grade.**
- **What:**
  - **The charge in three stems:** a base for every pull; a rise with timpani
    roll and cymbal for 4★ and up; a tell for 5★ only (a key change, a bell
    "ping" and a choir swell at 60%).
  - **Light & Dark:** the scroll adds a bell-tree and choir layer from the
    first frame.
  - **The burst:** a chime for 3★, a brass stab for 4★, and a gong and choir
    chord for 5★.
  - **The stars:** they climb up a glockenspiel scale.
  - **The music:** the island's music ducks under it.
  - **Other rites:** the awakening, the evolution and the relic awakening each
    get their own sound instead of reusing the summon burst.
- **Why:** Star Rail's upbeat 5★ music and Arknights' 6★ you can hear [checked].
  Today one file plays at two volumes [ours].
- **How:**
  - `sfx.py`, plus the VSCO sources.
  - `SummonRevealView.beginCharge` and `startWords`.
  - `AudioLibrary` gains a pitch parameter, `enableRate`, and
    `duck(to:fade:)`.
- **Cost:** free, a day. A synthesised brass is the lesser version; a recorded
  stinger is the upgrade (see the paid list).
- **Risk:** the tell must read `result.stars` and nothing looser. It must never
  fire on anything but a 5★.

**W2.8 Deaths that leave the field.**
- **What:** after the death clip:
  1. The figure fades over 0.7 s while a column of element motes rises.
  2. A small soul light lifts 2 m and winks out with a chime.
  3. A faint element glyph stays on the mark; a revive removes it.

  A boss sinks below the rim in dust instead.
- **Why:** Star Rail's and Genshin's dissolves [recalled], and "permanence"
  (Vlambeer) [recalled].
- **How:**
  - `UnitNode.markDefeated` schedules `dissolve()`.
  - The motes are an `SCNParticleSystem` with a cylinder emitter, and the host
    leaves through `VFXLibrary.retire`.
  - No custom shader: the run-235 rule.
- **Cost:** free, half a day.
- **Risk:** revive targeting must read the glyph.

**W2.9 The ultimate spotlight.** Needs L1.
- **What:** during an ultimate's wind-up:
  1. The SET's lights fall to 35% and the backdrop to 0.45.
  2. The camera's saturation drops 0.35 while the figures keep their colour.
  3. The set is released over 0.4 s after the blow.

  The white full-screen `ultimateFlash` becomes a two-frame exposure punch,
  which reads as light rather than as a UI flash.
- **Why:** Genshin's bursts and Star Rail's ultimates darken the world around
  the caster [recalled]. Today the caster competes with a fully lit orange
  world (`8-arena_battle-aoe-*`) [ours].
- **How:** `BattleSceneController.spotlight(on:duration:)` with an
  `SCNTransaction`. The brazier flicker reads a multiplier so it does not fight
  the dim.
- **Cost:** free, half a day.
- **Risk:** without L1 it dims the caster too.

**W2.10 Waves walk in.**
- **What:**
  - **Arrivals walk:** they play `.walk`, matched to their stride, instead of
    sliding.
  - **The stamp:** a carved "WAVE 2" or "FINAL WAVE" sweeps across with a drum
    hit.
  - **The opening:** the team walks on from behind the camera to its marks.

  At ×3 only the stamp plays, at half length.
- **Why:** Summoners War's team moves up between waves [recalled]. 115 walk
  clips ship [ours].
- **How:**
  - `place(combatants:entering:)` plays `.walk`, then the combat idle.
  - A `waveStamp` on the view model.
  - Warm the walk clip at the fight's start.
  - Re-time `6-battle-a` so it is not taken mid-walk.
- **Cost:** free, half a day.
- **Risk:** about 1.2 s more per wave; hence the ×3 rule.

**W2.11 The boss entrance.**
- **What:** a 2.4 s entrance at ×1:
  1. The HUD fades and the key light dims 40%.
  2. A rumble plays while the boss rises through thrown tiles and dust.
  3. It ROARS with its heavy attack, with a big shake and a heavy haptic.
  4. A wine ribbon, **BOSS**, carries its name and epithet.
  5. Its bar fills from empty.

  A Titan's ribbon shows its weakness colour.
- **Why:** Raid, Summoners War's dungeons and the Souls games' boss bars
  [recalled]. Today the Colossus's wave arrives as a quiet fade
  (`18-dungeon_battle-c`) [ours].
- **How:**
  - `bossEntrance(node)` in `BattleSceneController`, held by `holdOverride`.
  - A `bossTitle` on the view model.
  - The bar animates from 0.
  - Restore the lights on Skip and in `retirePreviousStage`.
- **Cost:** free, half a day.
- **Risk:** some bosses' heavy attack lunges; read each of the five on its
  board.

**W2.12 Missions: Claim All.**
- **What:**
  - **Claim All:** a CLAIM ALL plate appears when two or more rows are ready.
  - **Order:** ready rows sort to the top.
  - **The claim:** a claimed row stamps a gold DONE seal (with a thud and a
    small shake), dims, and slides to a Completed group.
  - **Bars:** they become 6 pt and gold, and pulse at 100%.
  - **The daily tribute:** its eight pills fill with ticks as missions finish.
- **Why:** Summoners War: Chronicles added "Complete All" [checked], and our own
  Codex already has one. Today the bars are hairline grey (`14-missions`) [ours].
- **How:**
  - `GameStore.claimAllMissions()` loops the existing claims until nothing
    changes, so the tribute unlocked by another claim is not missed.
  - Rows get stable `.id`s.
  - A `QuestTests` case: claim-all pays exactly what claiming one by one pays.
- **Cost:** free, a day.
- **Risk:** never reorder under a pressed finger.

**W2.13 The carved name card.**
- **What:**
  - **The plaque:** a dark glass plaque with a rim in the rarity's metal slides
    in from the right.
  - **The crest:** the element crest, 56 pt, at its left.
  - **The stars:** painted gold stars stamp in one by one, each with motes and
    a rising tick.
  - **The name:** carved gold, with a light sweep across it once.
  - **The second line:** epithet · pantheon · role, in cream.
  - **Chips:** NEW, the duplicate chip from W1.5, and FEATURED, pinned to the
    plaque.
- **Why:** Summoners War's, Genshin's and Raid's reveals are a designed
  object, not floating text [recalled]. Today's `5-reveal-b` is loose lines
  over clouds [ours].
- **How:**
  - A new `Pantheon/UI/Summon/RevealNameCard.swift` from `GlassPlate` and
    `ElementBadge`.
  - One `keyframeAnimator` replaces three `@State` timers.
- **Cost:** free, a day. An optional painted star is 6–9 credits.
- **Risk:** keep it in the right 45%, clear of the figure.

**W2.14 One continuous shot into the summon.**
- **What:** the room's scroll lifts off the ring and grows to the exact place
  where the reveal's scroll hangs while the room fades to dusk. The reveal then
  takes over with no system slide-up, so the player sees one object travel from
  the altar into the charge.
- **Why:** Summoners War's scroll flies into the circle on the same screen
  [recalled]. Today there are three separate beats: a dip, a sheet sliding up,
  and a second scroll [ours].
- **How:**
  - Set `revealResults` inside a `Transaction` with `disablesAnimations`
    (IslandView already uses this pattern).
  - An `openingScrollFrame` passed to the reveal.
  - The mileage and selector reveals get the same treatment.
- **Cost:** free, a day.
- **Risk:** check on the phone that no white frame flashes before the reveal.

**W2.15 The figure stages answer a touch.**
- **What:** in the Hall of Ka, the Collection stage and the reveal's hold:
  - **A tap** plays a flourish in turn: victory, a basic swing with a small
    element hit, or a flinch on a double tap.
  - **Idle:** after 12–18 s untouched the figure plays an idle flourish.
  - **Hold:** holding plays the ultimate's wind-up.
  - **Gaze:** the head turns (up to 25°) toward the finger.
- **Why:** Arknights' assistant reacts to a tap, and Genshin's idle emotes can
  be watched from the character menu [checked]. Today the figure only turns
  (`21-collection_stage`) [ours].
- **How:**
  - `UnitNode.flourish(_:)` chains `play(clip) { play(restingIdle) }`.
  - A tap recogniser does a `hitTest` on the figure.
  - An `SCNLookAtConstraint` on the Head joint at influence 0.3.
  - Effect hosts leave through `retire`.
- **Cost:** free, a day.
- **Risk:** check the gaze against the cape chain on the awakened Ares.

**W2.16 A colour grade per realm.**
- **What:**
  - **A colour script:** one line per realm, written into PLAN.md first, as a
    film does before shooting. Each line gives the light's hue, the shadow's
    hue and the one accent that glows. Examples: the Duat is warm gold light,
    violet-blue shadow and turquoise accent; Olympus is white-gold light,
    slate-blue shadow and gold accent.
  - **A LUT per realm:** each line is baked into a 3D colour table, so a warm
    set can have cool shadows under warm light. Boss stages get a darker
    variant.
  - **A check in CI:** `framelight.py` prints each frame's median and
    95th-percentile saturation and flags a realm that is over budget (set
    median at most 0.30, 95th percentile at least 0.75).
- **Why:** principle 1, measured. Summoners War's frames split warm keys from
  teal shadows [measured]. Its 13 lands each have one palette [checked count;
  palettes recalled].
- **How:**
  - `tools/lut.py` writes `Stage/lut_<realm>.png`. Its `--preview <frame>`
    applies a LUT to a CI frame offline.
  - `camera.colorGrading.contents` in `buildCamera` [checked: SceneKit takes a
    strip image].
- **Cost:** free, a day.
- **Risk:** author the LUTs against real frames made with the 1.85 white point,
  and mind the sRGB tag.

**W2.17 Carvings that glow.**
- **What:** each prop's painted gold or turquoise inlay is found in its own
  texture and lit in the realm's accent colour. It glows bright enough for the
  existing bloom to catch, breathing over 4 s. The floor inlay's grooves glow
  faintly too. Each realm gets one repeating glow colour, which gives the eye a
  path around the frame.
- **Why:** the owner's second frame: cyan runes on the statues and cyan rings
  in the floor are the only saturated colour in the set [checked]. Our props
  have no emission [ours].
- **How:**
  - `tools/prop_glow.py` writes `<prop>_e.png`.
  - `StageBuilder.loadProp` sets the emission and tints it in the prop's surface
    modifier.
- **Cost:** free, a day.
- **Risk:** the hue test can light a whole gold statue. Judge each mask on a
  sheet, and keep an exclusion list.

**W2.18 The trauma camera shake.** After the camera job.
- **What:** replace the sine wobble:
  - **Trauma:** each hit adds "trauma" (0.18 for a normal hit, up to 0.8 for a
    boss landing), which decays at 1.8 a second. The shake is trauma squared.
  - **The shake:** roll up to 2.2°, yaw and pitch 0.6°, and 3 cm on the
    camera's own axes, each from its own smooth noise.
  - **The kick:** 4–6 cm along the screen's hit direction.
  - **The rig:** the camera hangs under a rig, so the dolly moves the rig and
    the shake moves only the camera, and the two stop fighting.
- **Why:** Eiserloh, GDC 2016 [checked]. Today the shake moves along world x,
  partly toward the lens, and pulls the camera back to a stale point during a
  dolly [ours].
- **How:**
  - `CameraDirector.buildCamera` adds a `shakeRig`.
  - `addTrauma` is updated in `renderer(_:updateAtTime:)`.
  - Check that `projectPoint` still follows the shake.
- **Cost:** free, half a day.
- **Risk:** too much roll reads as "slanted", which the owner has rejected
  twice. Keep it at 2.2° or less and judge it on the phone.

**W2.19 A haptic vocabulary.**
- **What:** named Core Haptics patterns (Apple's library for custom
  vibrations):
  - a hit's strength follows its damage;
  - a crit is two sharp taps;
  - a kill is a tap and a falling rumble;
  - an ultimate's charge rises through the wind-up;
  - the summon charge rises, with a 5★ adding a quickening heartbeat;
  - the stars tick sharper each time;
  - a relic succeeds with two crisp taps, and fails with a dull rumble;
  - a claim is a cascade;
  - a wave and a boss arrive with their own patterns.

  A multi-hit plays full strength on its first and last hits only. Settings
  gets a **Vibration** toggle, on by default.
- **Why:** Core Haptics' intensity and sharpness, and Apple's advice to pair
  haptics with sound [checked]. Today there are three fixed taps and no toggle
  [ours].
- **How:**
  - A new `Pantheon/Core/Audio/HapticDirector.swift`, with its engine's stop and
    reset handlers, falling back to the UIKit taps.
  - `Juice.Profile.haptic` becomes a pattern.
  - `CoreHaptics` goes on swiftcheck's framework allow-list.
- **Cost:** free, a day. It can only be judged on the phone.
- **Risk:** a buzzing phone reads as cheap. Keep continuous events under
  400 ms, except for the summon.

**W2.20 A UI sound vocabulary.**
- **What:** about sixteen UI sounds that share one timbre: tab, back,
  open/close, toggle, select, coin tick, crystal tick, claim bell, deny, page,
  equip, lock, sell, hone, and others. Every UI sound varies its pitch by ±3–5%
  so repeats do not machine-gun. Haptics by meaning:
  - selection for chips and segments;
  - success for a claim;
  - warning plus the deny sound for "not enough".

  They live in the shared components (`PrimaryButton`, `BarButton`, the back
  medallion, the tab bar, `GamePressStyle`) with a `.gameSound(_:)` override,
  never as hand-placed calls.
- **Why:** a premium interface sounds like one instrument [recalled]. Today two
  sounds serve 125 call sites [ours].
- **How:**
  - `sfx.py build_ui()`, plus warm clicks picked from Kenney's CC0 interface
    packs, all through one chain.
  - iOS 17's `.sensoryFeedback`.
  - A 40 ms cooldown per sound.
- **Cost:** free, one to one and a half days.
- **Risk:** touches 32 files, so land it after the battle jobs. Pick wooden,
  stone and metal clicks; no bleeps.

**W2.21 Numbers that roll.**
- **What:**
  - **Rolling:** power, stats, level and XP, the relic's main stat, the pity and
    mileage chips, and the mission counts roll per digit or count up.
  - **Deltas:** a green "+26" (red for a drop) rises and fades beside a changed
    stat, and power pops 1.06 when it settles.
  - **Bars:** they fill on a spring with a travelling glint.
- **Why:** Star Rail's and Epic Seven's stat ticks [recalled], and "tween every
  change" [checked]. Today nothing in the tree uses `contentTransition` [ours].
- **How:** in `Components.swift`, `RollingNumber` and `.statDelta`, plus
  `.contentTransition(.numericText(value:))`, and a glint on `GlassMeter`.
- **Cost:** free, a day.
- **Risk:** `numericText` animates only inside a transaction. Animate locally
  on `onChange`.

**W2.22 Status effects that land.**
- **What:**
  - **New tiles:** a new tile pops in with a flash and four sparks.
  - **Expiring tiles:** an expiring tile shrinks away.
  - **Cleanse:** a cleanse wipes the red tiles.
  - **Attack-bar pushes:** a push floats a chip, "−50%" in red or "+25%" in
    blue.
  - **Head marks:** a stunned, sleeping or frozen unit gets a mark circling its
    head (stars, Z's or frost) from the head joint.
- **Why:** Summoners War names each effect as it lands [recalled]. Ours
  already floats each status's name in blue or red
  (`BattleSceneController.swift`, `.statusApplied`), so the new part is the
  tile's arrival, the cleanse and the push. Today a "push back 50%" reads as
  nothing happening, because `.attackBarChanged` only moves the bar [ours].
- **How:**
  - `UnitPlate.applyStatuses` diffs its tiles.
  - `.attackBarChanged`'s old value feeds a chip.
  - The head mark is a sprite ring, so no particle rule applies.
- **Cost:** free, half a day.
- **Risk:** keep the pop's temporary size out of the plate declutter.

**W2.23 Skip that never swallows a 5★.**
- **What:**
  - **Skip:** it jumps to the next unrevealed 5★ (or new 4★+), and says so:
    "Skip to ★★★★★".
  - **Hold to skip all:** a long press of 0.6 s, with a filling ring, skips
    everything.
  - **A tap during a 5★ charge** jumps to the flash, not past it.
  - **"Quick summons":** a setting that plays a 3★ single as a 0.5 s flash.
- **Why:** Genshin keeps the 5★ splash on skip [recalled].
- **How:** the Skip action in `SummonRevealView`, plus
  `onLongPressGesture(minimumDuration:perform:onPressingChanged:)`.
- **Cost:** free, half a day.
- **Risk:** tour step 5 and the stress loop.

**W2.24 The way into a fight.** After the camera job commits.
- **What:**
  - **No slide-up:** Fight or Begin no longer slides a system cover up over the
    map.
  - **The stage card:** the screen dips to the realm's painting with a carved
    card: realm · stage name, "3 waves", and the stage's power beside the
    team's. It holds for at least 0.6 s, and until the battle has drawn its
    first COMPLETE frame. Then it dissolves onto the field with the team on its
    marks, or walking on with W2.10.
  - **Effects drawn in advance:** while the card holds, every effect the
    fight can play is drawn once out of sight: each caster's element impact,
    the flipbook sheets its skills name, the cast ring and the standing sheet.
  - **The way out:** the same card in reverse, into the reckoning's world.
  - **Auto-repeat:** it shows the card on the first run only.
- **Why:**
  - Summoners War and Raid put a loading card between the map and the fight
    [recalled].
  - Run 221's lesson [ours]: a shader compiles the first time something is
    DRAWN with it, and the reveal's 21 shaders compiled at the flash and
    stalled a second. The battle parses its meshes in advance and draws
    nothing in advance, so its first ultimate is the likeliest stall.
    [Inferred; W2.26 measures it.]
- **How:**
  - Every `.fullScreenCover` that opens a `BattleView` (grep `BattleView(`:
    Arena, Labyrinth ×3, the island's guild war, the campaign) opens it inside
    `.transaction { $0.disablesAnimations = true }`.
  - `BattleView` starts in a `Phase.stageCard`.
  - `BattleSceneView` reports its first drawn frame once, through the
    `StageRenderGovernor` it already wears (`renderer(_:didRenderScene:atTime:)`).
  - `VFXLibrary.predraw(for:in:)` spawns each effect at 1% opacity behind the
    team and leaves through `VFXLibrary.retire`, the same way the reveal
    pre-draws its figure.
  - The tour photographs `6-battle-card`.
- **Cost:** free, a day.
- **Risk:**
  - Every pre-drawn host must leave through `retire`. A particle system left
    alive is run 239's crash.
  - The card must never hold longer than the build does, except for its
    0.6 s floor.

**W2.25 The lineup built by hand.**
- **What:** in `TeamPickerView`:
  - **Cards fly:** a card tapped in the roster flies to its slot and lands
    with a small pop and a tick. A removed card flies back. The model updates
    at once, so a fast picker never waits for a flight.
  - **The slot answers:** a filled slot glows in the unit's element. The
    leader slot's crown stamps in, and the leader line re-types when the
    leader changes.
  - **Resonance lights up:** a resonance the pick lights turns on with a chime
    and a light sweeping its line. A rank II gets a fuller chord.
  - **Power rolls:** the team's POWER stands on the rail and rolls with each
    pick (W2.21's `RollingNumber`). Where the picker has a stage, the stage's
    recommended power stands beside it and turns gold when met.
  - **The screen becomes a place:** it is the realm's painting under dark
    glass, as the briefing that opens it is, and no longer the cream page.
  - **The empty half of the rail** holds the lineup's matchup against the
    stage's waves, such as "Strong against wave 3's fire" or "Nothing strong
    against Apep".
- **Why:**
  - Every fight a player sets up starts here, and a pick today changes a
    number with no motion or sound, under half a rail of cream
    (`42-resonance`) [ours].
  - Summoners War's preparation screen puts the leader skill and the slots
    first [recalled].
  - Phase B's rule is that a place is its painting under glass [ours].
- **How:**
  - `TeamPickerView` (288 lines): a `@Namespace` and
    `matchedGeometryEffect(id: unit.id)`.
  - Diff `ResonanceService`'s lit set in `onChange(of: selected)`.
  - The power is a sum of `ResolvedUnit.power`.
  - The backdrop is `PlaceBackdrop`, chosen by the `slot`'s kind.
  - The matchup rail is a new optional `stage: Stage? = nil` parameter, so the
    three presenters still compile.
  - A tour frame of the picker mid-flight is not worth taking. Photograph the
    picker from the briefing (`42-resonance`) with a stage passed in.
- **Cost:** free, a day.
- **Risk:**
  - The three presenters must compile unchanged.
  - Flights stay under 0.35 s.
  - The matchup line must read the engine's own element table, never a copy.

**W2.26 Frame pacing measured, and the island smooth under the finger.**
- **What:**
  - **A frame meter on every stage:** each stage counts its own frame
    intervals on the render thread, and each tour step prints a line like
    `[Frames] battle p50 16.7 p95 18.1 p99 41.2 · 3 over 33 ms of 1,812`,
    also to More → Diagnostics. `ciframes.py` prints the line beside the step,
    so a hitch becomes a number rather than a feeling. It also checks W2.24
    (the first ultimate) and every later effect item.
  - **The island at 60 while touched:** it draws at 30 at rest (its native
    rate), but at 60 while a drag, a pinch, an `IslandReaction` or a
    decoration move is in flight (120 when the player chose it), and falls
    back to 30 half a second after. Its figures are laid out inside the scene
    from the painting's frame, so at 30 they trail the sand under the finger.
- **Why:**
  - "Inconsistent frame delivery feels worse than a stable lower frame rate",
    and "a large gap between the average and the 1% low suggests poor frame
    pacing" [checked: frame-pacing guides, Android's Frame Pacing docs].
  - We have a main-thread watchdog (`Perf`) and no frame count [ours].
- **How:**
  - `StageRenderGovernor` (GraphicsSettings.swift) already sits in front of
    every stage's render delegate. Record `renderer(_:updateAtTime:)`
    deltas into a fixed 256-bucket histogram, with no allocation per frame.
    Flush it when the stage disappears, and under `-tour` at each photograph.
  - The island: the drag and magnify gestures' `onChanged` in `IslandView` set
    an `isInteracting` flag, which `IslandSceneView.updateUIView` maps to
    `preferredFramesPerSecond`.
- **Cost:** free, a day.
- **Risk:**
  - The simulator's GPU is not a phone's, so read CI's numbers as trends
    between runs. The absolute numbers come from the phone's Diagnostics.
  - Keep every histogram write off the main thread.

**W2.27 Readable and touchable on the smallest phone.**
- **What:**
  - **Bigger targets:** the battle's gear, speed and auto controls keep their
    36-pt look but get 44 × 44 hit areas, with 8 pt between them.
  - **A second screen size in CI:** after the main tour, CI photographs seven
    screens (battle, summon, unit sheet, team picker, island, chapter map,
    relic inventory) on the smallest landscape phone the iOS 17 target
    admits: the iPhone SE (3rd generation), 667 × 375 points with no insets.
    It photographs the same seven on one iPad, since the app runs there too.
  - **A decision point for the iPad frames:**
    - If they are broken beyond a day's work, the owner chooses between fixing
      them and shipping iPhone-only (`TARGETED_DEVICE_FAMILY = 1`).
    - If they hold, they are also the App Store's iPad screenshots, which an
      app that runs on iPad must supply [recalled].
- **Why:**
  - Apple's minimum hit target is 44 × 44 pt [checked].
  - The Game Accessibility Guidelines ask for virtual controls that are
    "large and well spaced, particularly on small touch screens" [checked].
  - Every frame judged so far comes from one iPhone 15/16-class simulator
    (`build.yml`), and the fixed widths (the team picker's 300-pt rail, the
    unit sheet's three columns) were fitted to about 852 points [ours].
- **How:**
  - In `BattleView.squareControl`: `.padding(4)` and
    `.contentShape(Rectangle())` round the 36-pt label.
  - In `build.yml`, after the main tour: `xcrun simctl create` an SE and an
    iPad, run the seven steps by name, and suffix the frames `-se` and `-pad`.
    `ciframes.py` groups them. Seven steps are about six minutes of the
    90-minute limit.
- **Cost:** free, half a day and one CI run to read.
- **Risk:** the runner may lack the SE's runtime. If it does, use the smallest
  iPhone it lists, and name it in the report.

**W2.28 The arena as a contest.**
- **What:**
  - **A VS card:** it opens an arena, draft or guild-war fight in place of
    W2.24's stage card. The two demigods' names and ranks with their crests,
    the two lineups' faces across a diagonal, and the two powers show for
    1.2 s, with a drum and a sword ring.
  - **A promotion ceremony:** when a World Arena result crosses a tier
    threshold, the old crest cracks, the new one stamps in with its name, rays
    turn and the fanfare plays. The draft's "A new crown" title
    (`DraftView.swift:535`) uses the same ceremony.
  - **The points roll:** the reckoning rolls the points, "1,860 → 1,875 (+15)".
- **Why:**
  - The tiers exist (`ArenaService.applyResult`, `player.arena.tier`), and
    crossing one says nothing [ours].
  - Raid and Epic Seven open their PvP fights on a two-team card [recalled].
- **How:**
  - `ArenaService.applyResult` also returns the tier before and after (an
    added tuple member; grep `applyResult(` and `ArenaTests`).
  - `BattleSummary` carries it.
  - A shared `PromotionCeremony` view goes in `Pantheon/UI/Arena/`.
  - The VS card is a variant of W2.24's card.
  - The tour flag `-tour-arena-promote`.
- **Cost:** free, a day.
- **Risk:** the addition to `applyResult` must be additive, with the tests
  changed in the same commit.

### Wave 3: after that, free but bigger or dependent

Ranked. Each has fewer details here; the researchers' full notes are in the
workflow's return and can be expanded when an item is picked up.

| # | Item | Impact | Effort | What and why, in brief |
|---|---|---|---|---|
| W3.1 | Rewards fly into the wallet, and the purse counts up | 5 | 4 | 6–12 copies of each icon burst from the claim button and home in on their wallet chip, which pops and counts up; relics and scrolls fly to the tab that holds them. The genre's currency flow and Cookie Run's top bar [checked]. **Needs W3.2 first**, because a system sheet cannot reach the shell's overlay. `RewardFlightLayer` in `RootView`, anchors from `BarWallet`/`IslandPurse`, a trailing `WalletDisplay`, `coin_tick`/`crystal_tick`. About two days. |
| W3.2 | Screens open inside the game (an in-shell presenter) | 4 | 4 | The bazaar, Missions, Events, Allies, Decorations, the Hall of Ka and the Labyrinth stop sliding up as iOS sheets. The island camera pushes toward the building, the screen fades and scales in over it, and tabs crossfade. `GamePresenter` in `RootView`. Settings stays a sheet. The risk is releasing SceneKit views on pop. About 2.5 days, done screen by screen behind a flag. |
| W3.3 | The island's paths: six figures walking between places and doing things there | 5 | 4 | A path network measured on the painting (`mapgrid.py`); figures walk it with their walk clips, face a placed brazier, spar in pairs at the arena mouth, greet each other where they meet. Summoners War's wanderers, and Cookie Run's cookies using the decorations [checked]. `IslandDatabase.paths`, a polyline walk in `IslandSceneView`. Two to three days. |
| W3.4 | Speech bubbles from the figures | 4 | 2 | One line every 25–40 s or on a tap: a reminder that opens its place ("Energy is full — the Gate is waiting.") or a line of flavour by pantheon. The tone stays serious. Ellia's bubbles [checked], Arknights' assistant [checked]. New `IslandChatter.swift`. Half a day plus writing. |
| W3.5 | The newest god walks out of the Summoning Circle | 4 | 2 | After a 4★+ summon the circle flashes, and the new unit rises at the pool and walks to a stand with "NEW · Sekhmet" over it. A non-saved `recentSummonIDs`; warm the mesh at the end of the reveal. Half a day once W3.3 exists. |
| W3.6 | Attention badges derived from state | 4 | 3 | Red dots (and a gold "!" for new content) on the tab doors, stalls, banners and cards, computed from the player's state alone so a dot can never be stale. Summoners War: Chronicles ships red dots and fixes stale ones in its patch notes [checked]. `AttentionService`, `AttentionBadge`, `AttentionTests`. A day and a half. The rule: only "something to take or do now". |
| W3.7 | Buildings visibly grow with their tier, with a ceremony | 4 | 3 | Tier II adds braziers from the bundle's props, tier III columns or a statue and a rim glow. The first sight of a tier glides the camera over for a dust burst, a thud and a carved "HALL OF KA · II". Cookie Run's castle levels [checked]. `Landmark.dressing`, `Player.islandTiersSeen` (Optional). Staggering the buildings' unlock levels is **the owner's call** (it changes the first hour). A day and a half. |
| W3.8 | A 28-day login calendar that opens on the day's first visit | 4 | 3 | A 7 × 4 board over the dimmed island, today's seal stamping in, and a missed day that WAITS instead of restarting. Summoners War's monthly check-in [checked]. **An economy decision:** a month pays more than four weeks of the 7-day loop, so price it with `balance.py --login` first. Whether day 28 pays a Light & Dark scroll is the owner's call. `Player.loginMonth` (Optional). |
| W3.9 | The AVAudioEngine rebuild: buses, pitch, pan, ducking, reverb per realm | 4 | 4 | Five buses (music, effects, UI, voice, ambience), round-robin variants, pan from the victim's place on screen, a cap on simultaneous starts, and a reverb preset per realm. It keeps `AudioLibrary`'s public API, so the 125 call sites do not change. It proves itself through `[Audio]` console lines, because CI cannot hear. It must handle route changes. A day and a half. |
| W3.10 | A score per realm, rendered offline for free | 5 | 4 | About 18 cues written as notes and rendered with fluidsynth through MuseScore_General (MIT) plus VSCO-2-CE percussion (CC0), mastered with pedalboard. Each realm gets its mode and instruments: Hijaz and reed for Egypt, Dorian and harp for Greece, Aeolian, horns and war drums for the Norse, brass for Rome, pentatonic koto, shakuhachi and taiko for the Jade Court. Genshin's per-region orchestras [checked]. **A prototype was rendered here (a victory fanfare and a Jade motif in `scratchpad/audio`); nobody has listened to it.** Honest ceiling: good indie quality, below a recorded score. Two to three days; +14 MB bundle. |
| W3.11 | Adaptive battle music | 4 | 3 | Intro, realm loop, a boss theme switched on the bar, the loop stopped for the victory stinger, a results loop, and a 7 dB duck under an ultimate or a boss line. Needs W3.9 and W3.10. A day. |
| W3.12 | Ambience beds per realm and on the island | 3 | 2 | Desert wind and brazier crackle, cave drips, surf and gulls, wind and ice, a fountain, birdsong and chimes, and crickets on the island after 20:00. `tools/ambience.py`. Leave out any that sounds synthetic. A day. |
| W3.13 | Mix, formats, volume sliders | 3 | 2 | Loudness targets checked by pyloudnorm, music and ambience shipped as AAC, sliders for Music, Effects and Voices in Settings, and `[Audio]` lines under `-tour`. |
| W3.14 | Continuous day and night, lit by lamps | 3 | 2 | About seven keyframes blended by the minute instead of four hard switches; at night, light pools at the braziers, the flame, the Hall's doorway and every placed brazier, and stars over the sea. `IslandDaylight`. A day. |
| W3.15 | The island breathes | 3 | 2 | Soft cloud shadows drifting over the island, and a loose flight of birds across the sea every 20–40 s. The sound half is W3.12. A day. |
| W3.16 | Living set pieces in every realm | 4 | 3 | Two or three things that move in each realm: a light beam behind the far parapet (the owner's fountain beam), the orphaned `hangingRocks` revived as sky debris, banners swaying, rune rings turning, waterfall sheets. Slow motion on the edges and the back only. One and a half to two days. |
| W3.17 | A set-dressing plan in three bands | 4 | 3 | A centrepiece at the back, a RHYTHM of one repeated piece along each side wall, clutter from props already in the bundle, and low framing pieces in the corners, darkened. The owner's frame shows exactly this [checked]. Place it after the camera job lands. |
| W3.18 | A sky that moves | 3 | 2 | Cloud shadows drifting over the arena floor, a sea of cloud below the far edge (the floating arena), and a mist band for parallax. Move the NODE, never `contentsTransform`. |
| W3.19 | Built Norse, Roman and Jade props (free half) | 3 | 3 | Octagonal timber pillars with knotwork, rune stones, lanterns with emissive paper, and stone lions built from boxes and cylinders with drawn textures, in place of the Greek stand-ins. The Meshy half is on the paid list. |
| W3.20 | Per-pantheon summoning circles | 3 | 2 | Norse (slate, ice, the world-tree root, snow), Rome (marble, broken columns, crimson standards) and the Jade Court (moss, a red lacquer gate, petals, lanterns), plus a dusk tint per pantheon. A `switch` over `Pantheon` in `buildSummoningCircle`. A day. |
| W3.21 | The featured gods on the summon screen | 3 | 2 | The banner's painting (twelve ship, unseen) as a framed band, with the featured faces and "RATE UP ×2". `BannerHeroBand` with `PaintingFill`. A day. |
| W3.22 | Figure screens with a soft painting, an element rim and a turntable | 3 | 2 | The shared Core Image blur behind the figure, darkened round it; the rim light moved behind and tinted by element; a slow turntable on the Collection stage. Half a day. |
| W3.23 | A game dialog instead of the 13 system alerts | 3 | 3 | Marble, the ribbon, and the game's buttons. The sell confirm shows the relics sold and the drachma gained. The battle's gear menu becomes a glass column. Keep the system alert only for the fatal-error fallback. A day and a half. |
| W3.24 | Ambient life on the cream screens | 3 | 2 | A parallax tilt on the unit sheet's big card (CoreMotion), light travelling round anything claimable, and a slow light across the panel corners. One shared clock; off under Reduce Motion. A day and a half. |
| W3.25 | Baked ambient occlusion in the figure textures | 4 | 3 | Offline, 35–50% occlusion and a slight head-to-feet gradient baked into each base texture, the genre's painted-in shadow inside our physically based figure, with no cartoon ramp. `tools/bake_ao.py` with pymeshlab. Then test whether SSAO can drop. Mirrored UVs double the AO, so judge on a board and exclude those. |
| W3.26 | A soft contour round each figure (mask pass) | 4 | 4 | An `SCNTechnique` that draws the units into a mask and lays a soft dark 1.5–2 px edge outside the silhouette: a shadow edge, not an ink line. The same mask can keep the figures in colour during W2.9's dim. Metal cannot be compiled here, so expect two or three CI runs. The owner has rejected cartoon outlines, so it is one flag to turn it off. |
| W3.27 | Boss pocket, and the Light & Dark signature | 3 | 2 | On a boss wave the set behind the boss drops 30%, a cool rim outlines it, and one emissive tell glows (the Colossus's core, the King's eyes). Light and Dark units get a slightly stronger element-tinted rim and a faint pool of light under them. Needs L1 and W2.17. The premium look must be shown to the owner on the reveal lab first. |
| W3.28 | Compressed textures and a heat governor | 3 | 3 | ASTC textures, about 8× less texture memory than the decoded RGBA, loaded through `MTKTextureLoader`. When the phone runs hot (`thermalState`), SSAO turns off, shadow samples halve, and at critical the game runs at 30 fps. Pays for the other items on the phone. Keep the PNG fallback. |
| W3.29 | A share card for a 5★, and pity worded as an honour | 3 | 2 | A Share button builds a 16:9 image from the stage's frame and the name card; a pity 5★ reads "Your devotion answered — 90th scroll" on a gold ribbon. `ImageRenderer` and `ShareLink`, plus an `Analytics` event. |
| W3.30 | The first five minutes, storyboarded | 4 | 4 | Today a new player sees key art, then a sign-in button, then a cream menu with Athena, and no spectacle before any of it (`24-launch`, `48-sign_in`, `30-guide`) [ours]. Genshin and Star Rail open on a cinematic, and Raid's and Epic Seven's tutorials lend the player overpowered heroes for the first fight [recalled]. **(a) Free:** a title cue on the launch screen, where the island loop plays today (W3.10 renders it). The sign-in then dissolves into the island while the camera settles from 1.6× on the Summoning Circle to home over 2.4 s, with `IslandCamera.aimed`, as the tour's zoom does. **(b) Free:** a prologue fight, *The Waking*. Three awakened 5★s on loan at level 40 fight one Titan in one wave, with the cut-ins (W2.1) on. It ends as the loan is taken back and Athena hands over the first scroll. It is a `BattleContext.prologue` that pays and saves nothing but `Player.prologueSeen` (Optional). **(c) The owner's call:** whether the prologue exists at all, since it changes the first hour. Storyboard it in PLAN.md with frames first. Two days. |

### What costs money, with prices

Nothing here is needed for Waves 1–3. Every item is the owner's word only.

The Meshy balance was 594 on 2026-09-23. The researchers worked to a 500 floor,
so run `python3 tools/meshy.py balance` before any launch. Gemini is paused
except on his word for a named batch, capped at $10 a month.

| Item | Tool | Price | Note |
|---|---|---|---|
| The missing realm props: hall pillar, pagoda lantern, rune stone, Norse brazier, stone lion, longship prow | Meshy (a 6-credit concept, then 30 image-to-3D) | about 36 credits each; about 216 for all six | About 94 credits spare today buys two. The hall pillar goes first (four places in Jötunheim and the fjord), then the pagoda lantern (both Jade sets). |
| Painted action icons (two sheets: power-up, evolve, awaken, sell, lock, equip, filter, sort, lore, back…) | Meshy picture | 12 credits (26 with a re-roll each) | Retires the last system glyphs in the chrome. Paint them bold; tiny icons can blur into nothing. |
| A painted turn sigil, a card back for the ten-pull board, a painted star for the name card | Meshy picture | 6–9 credits each | Code-drawn versions come first. |
| A pagoda gate and a runestone for the summoning circles | Meshy | 30 each | Code-built pieces are the free version. |
| A bespoke "greet" motion for the Hall of Ka | Meshy text-to-motion | about 13 credits a family | For a handful of heroes, once credits allow. |
| The realm themes from Lyria 3 (8 cues × 3 takes) | Gemini API | about $0.96 on Clip, $1.92 on Pro | Prices are from search summaries; the first call confirms them. The owner reads the terms for AI music and the SynthID watermark before release. The free W3.10 renders make the stingers either way. |
| Voiced boss lines and god barks | Gemini TTS | about $0.10 for phase A (about 35 lines), $0.60 for phase B (about 240) | Voices are described, never modelled on an actor. Audition phase A first: TTS roars can sound comic. ElevenLabs acts better but its host is refused here. |
| A painted night version of the island | Gemini | about $0.14 (one image) | Crossfaded in by W3.14. |
| Painted tier-III buildings | Gemini | about $0.84 (about six images) | The prop-built tiers of W3.7 are the free version. |
| A recorded summon fanfare | a licensed library or a composer | not priced | No licensed source is reachable from here. The synthesised brass of W2.7 is the lesser version. |

**Owner decisions that are not about money:**

- A real **Crushing Hit** (W1.2's note).
- Staggered **building unlocks** (W3.7).
- The **login calendar's** value and day 28 (W3.8).
- The **Light & Dark signature** look (W3.27).
- The **prologue fight** in the first five minutes (W3.30).
- **iPad**: fix the 4:3 frames or ship iPhone-only (W2.27), once the iPad frames have been seen.

**Handed to the lighting job, from the art research:** the fjord and Jötunheim
floors read as water in `29-realm_battle-b` and `-c`.

---

## 4. The ten to do first

In order: impact over effort, and ties broken by how often a player sees the
thing. Each can be approved with one word ("yes", "no" or "later"). Every one
is free. Each ends with its CI frames, or its audio page, sent to the owner
before he tests.

1. **Speed ×1/×2/×3, remembered, with the juice kept at ×3 (W1.1).** Today the
   button steps 1 → 2 → 4 and at ×4 silently switches off every freeze, shake
   and haptic. Auto farming is where players spend most of their time.
2. **Damage numbers that read (W1.2).** The crit's "!" and the glance's suffix
   become CRITICAL and GLANCING as words over the number. Crits get bigger and
   gold, a multi-hit ends on a gold TOTAL, and green means heals only. Today an
   advantage hit shows in the heal's green.
3. **A hit-stop that grips, and an impact frame (W1.3).** The victim trembles
   inside the freeze, the freeze grows with the damage as well as the weight,
   and crits and kills get a two-frame colour punch.
4. **One press language, one set of motion curves, and 120 Hz unlocked
   (W1.8).** Every button sinks, springs back, clicks and ticks on touch-down;
   today 69 buttons give no feedback at all. One missing Info.plist key holds
   every animation on a Pro iPhone to 60 Hz and hides the 120 setting. This is
   on every tap in the game.
5. **The summon's rarity ladder, and honest duplicates (W1.5).** Every charge
   starts the same and climbs to violet and then gold with lightning, and a
   duplicate says which skill really levelled.
6. **The player's level-up fanfare (W1.6).** LEVEL 8, energy refilled, max
   energy +2, +25 divinity, and anything unlocked. Today it happens in silence.
7. **The silent fight gets its sounds, and victory plays once (W1.4).** Heal,
   shield, buffs, debuffs, resist, counter, extra turn, revive, death, wave and
   boss all get a sound, and a listening page goes to the owner with them.
8. **The turn circle, and the skill word made a banner (W1.9).** A glowing rune
   disc under the acting unit, and the skill's name that floats today becomes
   its icon and name in a gold frame, as in your Summoners War frame.
9. **The end of a fight (W1.7).** The final blow in slow motion, then the team
   turns to face the camera and plays its victory clips while EXP fills and
   VICTORY is stamped over the live field.
10. **The unit sheet stands the god up (W1.10).** The sheet a player opens most
    shows the serious 3D figure the roster was remade into, turnable, in its
    own dark well, with the card one tap away. Today it shows a 150-pt chibi
    card.

**Handed on, not dropped:** figure-first light (L1) belongs to the lighting job
running now, and comes first after it if that job leaves it undone.

---

*Sources.* The full source list (URLs, the frames looked at, and the code read)
is in the six researchers' returns for this workflow run. The facts that matter
are marked [checked] or [recalled] above. Refused by the network policy and not
used as sources: the Summoners War, Cookie Run, Arknights and Genshin fandom
wikis, namu.wiki, GameWith pages, ArtStation, GDC Vault PDFs, BlueStacks,
Gamerant, archive.org, kenney.nl, freesound, Suno, Udio, ElevenLabs and
ai.google.dev.

*Sources added on the art director's pass* [checked, from search results'
summaries]: Apple, *Optimizing iPhone and iPad apps to support ProMotion
displays* (developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
and the developer-forum thread "SceneKit 3D rendering limited to 60Hz on the
new iPhone 13 Pro?" (developer.apple.com/forums/thread/690806); the 44 × 44 pt
minimum hit target from Apple's HIG as summarised by uxcel.com and
evinced.com; Game Accessibility Guidelines, "Ensure no essential information
is conveyed by a fixed colour alone" and the full list
(gameaccessibilityguidelines.com/full-list/); frame pacing from Android's
Frame Pacing library page (developer.android.com/games/sdk/frame-pacing) and
wayline.io's *Frame Pacing: The Key to Smooth Mobile Games*. The Summoners
War, Genshin, Star Rail, Raid and Epic Seven screen descriptions on that pass
are [recalled]: searches for their team, character and PvP screens returned
nothing that describes them.
