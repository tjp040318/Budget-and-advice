# Playtest checklist

What to look at on the phone, in order, and what to send back. Each item says
what "right" looks like so a wrong one is obvious. The game is **landscape
only** now: hold the phone sideways; it will not rotate to portrait.

```bash
cd ~/Pantheon && git checkout claude/greek-gatcha-game-base-clfzlj && git pull
```
Then **⌘R** in Xcode. You no longer need the console open: **More →
Diagnostics** on the phone holds everything the app printed, with Copy and
Share.

## How to report

Open the **Playtest Log** page (the link is in the chat) and log each thing
you see: what happened, which screen, how bad. Then tell the session "check
the issues log". Screenshots still go in the chat. The console block below
goes into the log's details field or the chat, either is fine.

## 0. The island

The app opens on a wide painted island at dusk, sun at the upper right. Five
plaques, each **on its building**: the pillared hall at the upper left, the
twin-pylon gate at the lower left, the ring of pillars around the pool in the
middle, the oval arena at the lower right, the obelisk at the upper right
(plaque under the shaft). Nothing is cut off by the header or the tab bar.
The ones with something to do glow. Tap **Hall of Ka** and the training
screen opens over the island; tap **Gate of the Duat** and the Campaign tab
opens; tap **Summoning Circle** and Summon opens.

Send: a screenshot. If a plaque is off its building, say which and which way.

## 1. The console block, from More → Diagnostics

Open a battle or a summon first, then **More → Diagnostics → Copy all** and
paste it. The first line names the build and the device. Then, the first time
a model was loaded:

```
[ModelLibrary] 3D files actually inside the app: 90
[ModelLibrary]   OK       anubis -> anubis.usdz
[ModelLibrary]   OK       ares -> ares.usdz
[ModelLibrary]   OK       zeus -> zeus.usdz
[ModelLibrary] 'anubis' built 1 node(s) of interest:
[ModelLibrary] model: 1 textured material(s); the 45° costume accent becomes 165° for #7FE0C8 in the surface shader
[ModelLibrary] 'anubis': 1 skinner(s) rebound to this instance's own bones
[ModelLibrary] 'anubis': measured x1.11 y2.05 z0.42, 2.1 units → 2.05 m (×0.9991)
[ModelLibrary] clip animation taken from … , 1.67 s, a group
```

- **90 files** — eight per family for the ten modelled families, plus ten stage props. The Shabti have
  no models by design.
- **`y 0.00..2.05` and `×1.0000`** — the file is canonical and the game did
  nothing to it. Sekhmet reads `y 0.00..2.00`, Zeus `y 0.00..2.15`.
- **`clip animation taken from …, a group`** is the good case. **`assembled
  from N joint tracks`** means the importer split the clip and the loader
  stitched it; also fine, and worth knowing. **`a single track`** means the
  fix did not engage; paste the block.
- **`MISSING`** or **`could not open it`** — paste the whole block.

## 2. Collection

- **Every card is a painted, stylised portrait** of the same design as the
  model — chunky, cel-shaded, Summoners War proportions: Anubis, Sekhmet,
  Zeus, Ares (bronze Corinthian helmet, crimson plume), Heracles (lion pelt
  hood), Perseus (winged helmet), Hoplite, Satyr (vine wreath, pan-flute),
  Harpy (dark wings) and Thoth (an ibis bust), each in five element
  colours, and the Shabti (a cracked stone figurine) in five. A letter on a
  gradient anywhere means a filename is wrong; say which card.
- Six or more cards across, the grid fills the width.
- **Train** at the top left opens the Hall of Ka.
- Tap a unit: the detail screen opens.

Send: one screenshot of the grid.

## 3. Unit detail — Overview

- Every stat shows its **base** number and, when relics are equipped, a
  **green +N** beside it. Equip or remove a relic on the Relics tab and come
  back: the green number changes, the base does not.

## 4. Summon

- Three banners: **The Duat Opens** (Egypt), **Olympus Stirs** (Greece) and
  **The Endless Scroll** (everything).
- **A banner gives only its own pantheon.** Ten pulls on Olympus Stirs are
  all Greek: mostly Hoplites, Satyrs and Harpies (3★), some Heracles and
  Perseus (4★), a Zeus or Ares at 5★. Ten on The Duat Opens are Egyptian:
  Shabti, Anubis (4★, **four stars on the reveal**), Sekhmet or Thoth. An
  Anubis or a Shabti out of the Greek banner, or ten identical fire Anubis,
  is the old build; pull again after checking the build date.
- The reveal stage is a **stone summoning circle**: a glowing rune ring on a
  round dais, on a floating rock, with a half-ring of pillars and two
  braziers behind the figure (Egyptian lotus columns for an Egyptian unit,
  Greek columns for a Greek one), mist and dust, the glow and rays behind.
- The reveal: **dark charge → white flash → figure springs in on the left,
  slowly turning → stars tick in on the right → name slams down → details
  fade in**. The figure is the stylised model — Sekhmet a black lioness in a
  gold sun-disc crown with a crimson skirt and a gold khopesh, her lapis and
  crimson still their own colours under the element's tint. A grey dot or a
  letter plate in place of a figure means the model did not load — paste the
  console block.
- Tap during the sequence: it completes instantly. Tap after: next result.

Send: a screenshot at the moment the name is on screen.

## 5. Hall of Ka

Open it from the island or from Collection → Train.

- **Power up**: pick a target at the top, tap Shabti in the Feed grid. The
  Result panel shows experience, the level it will reach, the drachma cost,
  and **Skill-ups ×N** if any fed unit is the same character as the target.
  Tap **Power up**: the fed units are gone, the level has risen, a gold line
  at the top says what happened. Feed an Anubis a duplicate Anubis of the
  same element and check the Skills tab afterwards: one skill is a level up.
- **Evolve**: needs max level and same-grade fodder; the requirement rows
  tick green as they are met. A 3★ Shabti at level 35 with three 3★ Shabti
  fodder and 8,000 drachma becomes a 4★ at level 1.
- **Awaken**: the essence rows show have / need; the button enables when all
  are met. Essences drop in the campaign.
- **Awaken** also shows the two forms side by side — the card the unit has
  and the awakened card it becomes, with the new name — before you pay. Tap
  **Awaken** with the essences in hand: the summon reveal plays, the figure
  comes in glowing under the new name with **AWAKENED** beneath it, and from
  then on the collection, the team strips and the battle plate show the
  awakened card. In battle the awakened unit's costume glows in its element's
  colour, its rim light is brighter and a slow rise of light comes off its
  feet. The starter Anubis in a fresh tour save is awakened, so the CI frames
  show one.
- Locked units never appear as fodder.

Send: a screenshot of the Result panel before you tap Power up, and one of
the Awaken panel's two cards.

## 6. Battle (Campaign → Reed Fields), with Sekhmet or Zeus on the team

- **Landscape framing**: one row across the top (flag, stage name, the turn
  order faces, AUTO, ×1, log), an open middle, and a bottom bar with the
  actor's plate at the left and the skill buttons at the right. Your line
  stands in the open middle, about a third of the screen tall, feet near the
  bottom; the enemies stand behind them, heads below the top row.
- **The stage is a 3D set now**: a broken stone platform floating in the air,
  a painted sandstone floor with a cliff edge and boulders, colossal seated
  Anubis statues and obelisks at the far edge, lotus columns behind the
  enemies, braziers burning at the corners with flickering light, mist
  drifting at the edges, dust in the air, and the stage's painting far
  behind, with its land showing below the platform's edge. When the camera
  leans into an action the set shifts against the painting. Say if a statue
  faces the wrong way, floats, or blocks a unit; if the floor pattern is too
  big or too small; if the fire is too bright.
- **The characters are stylised now** — five heads tall, big hands, chunky
  armour, painted textures, the same design as their cards: Anubis in a
  striped nemes and a gold-and-lapis collar, Sekhmet as above, Zeus in gold
  scale over a white himation with a bolt in hand. Realistic proportions or
  marbled tan bands mean an old file is still in the build.
- **Look**: every model has a thin edge of light in its element's colour,
  lifted shadows with a painted two-tone feel, and its gold turned to the
  element's colour — a tide Anubis wears blue-green where the ember one
  wears orange, with the fur, skin, white cloth and the design's other
  colours unchanged. Say if anything looks flat, or if a colour landed on
  skin.
- **Melee attacks close the distance.** Anubis, Sekhmet, Ares, Heracles,
  Perseus, the Hoplite, the Satyr and the Harpy dash up to their target,
  turn to face it, swing, and walk back when the next turn begins. Zeus and
  Thoth cast from where they stand. Every hit flashes the victim white for a
  blink, and the camera leans a little into each action and settles back.
  Say if a dash overshoots, if someone is left standing in the enemy line,
  or if the camera ends a turn somewhere odd.
- **Idle**: the units breathe in a combat stance from the first second.
  Arms straight out and legs straight is the A-pose; it was a one-line bug
  in the battle unit and should be gone. If you see it, paste the console
  block.
- Sekhmet and Zeus stand the same way, a little taller than Anubis. Zeus's
  Thunderclap puts forked lightning across the enemy line and cracks.
- Attack. On the hit: freeze, shake, tap, an oversized number, a thud.

Send: a screenshot mid-battle, and a sentence on whether the framing feels
like a game or like a diorama seen from a ladder.

## 6b. Arena (Arena tab → pick an opponent → Attack)

- Four against four on the arena stage. Your four stand in two ranks in the
  lower half, the back pair between and behind the front pair; the enemy
  four the same way beyond them. Everyone's feet are on screen; nobody is
  hidden behind anybody.
- The enemy team is built from the whole roster, so this is where the new
  characters show up as opponents too. Say if any stand in an A-pose or as a
  grey stand-in.

Send: a screenshot before the first command.

## 7. More

- **Diagnostics** → the console, Copy all, Share.
- **3D assets** → the ten modelled families green; the Shabti and the enemies
  grey, which is expected.

## 7b. Five tabs and the Obelisk

The tab bar shows Island, Campaign, Arena, Summon and Collection, all five
at once. **More** (account, sound, the console, the bazaar, missions) opens
from the island's **Obelisk** plaque and slides up as a sheet with a Close
button. It is no longer a tab, because an iPhone folds a sixth tab into a
"More" list of its own.

## 8. The island's figures

Back on the island: your campaign team stands on the sand — below the pool,
in the middle of the island and on the front beach — in their combat idles,
each on a soft shadow, about a tenth of the screen tall, facing you. Sparks
rise off the pool; a flame flickers at the obelisk's tip. After dark the
painting goes blue; at dusk, warm. Tapping the wallet in the header opens
the bazaar.

Send: a screenshot. If a figure floats, sinks or stands on a building, say
which spot. If the island stutters for a second when it opens, say so (the
models load on first sight).

## 9. Campaign → Halls of Essence

Campaign has two segments at the top. **Halls of Essence** lists five halls,
one per element, each with five floors (B1–B5) and a BOSS tag on every
floor. B1 is open; B2 opens when B1 falls. The briefing shows the floor's
enemies (three creatures and the element's boss), the element essence in
the rewards, and a **Repeat** row. Clear B1 twice: the second clear still
pays drachma and a relic chance, but no first-clear divinity.

Send: which floor you reached with which team, and whether B3 felt like a
wall (the simulator says it wants 5★s with relics).

## 10. Repeat runs

In any briefing, pick **×5** and Begin. The fight runs on auto; between
runs a "Run 2 of 5" line shows for a moment and the stage rebuilds; the
HUD's ↻ 2/5 counts, and tapping it stops after the current run. At the end
one panel lists the runs won, the drachma, the EXP, the relics by grade
and the essences. It stops early on a loss or when the energy runs out,
and says so on the panel. The wallet bar shows **m:ss** to the next point
of energy whenever you are under the cap.

Send: the final panel, and whether the countdown matched the energy tick.

## 11. Relics

Collection → **Relics** (top right). The set tallies at the top (7/2
Fury…), slot chips, Unequipped, a sort and a role menu. Every row has an
efficiency ring. **Select** → tap a few → **Sell for N**: equipped ones
come off their units; a locked one refuses to be picked (a warning
buzz). Tap a row: Upgrade, Reappraise (from +9), Lock, Sell, Unequip. On a
unit's sheet each relic slot has **Choose**/**Change**, opening a picker
sorted for the unit's role.

Send: anything that sold that should not have, and whether the efficiency
numbers agree with your eye (a 6★ with four good subs should be green).

## 12. The bazaar

From the island's wallet or More → Bazaar. Claim the **Daily offering**
(a scroll, 2,000 drachma, 10 energy); the button then reads Claimed until
tomorrow. Buy an energy pack and watch the wallet bar. A relic pack lands
in the inventory at the grade on the label. Nothing here costs real money.

Send: the receipt line after a purchase, and the wallet before and after.

## 13. The campaign map

Tap the **Gate of the Duat** on the island and you are on the map: a strip
of chapter chips along the top (gold where you are, a tick where a chapter
is done, a lock where its gate is shut) and, below it, the chapter you are
in — the stage's painting with a dotted road across it and a medallion per
stage: gold with a tick where you have been, a pulsing ring where you
stand, a lock beyond, a crown on the boss. Tap the ringed one and the
briefing opens; the list under the map does the same. **Realms** (top left)
opens the overview of the three realms and says which boss shuts what.
Every tap here should land: if a medallion, a chip or a row ignores you,
say which.

Send: a screenshot of the map as it opens, and whether it opened on the
chapter you are actually in.

## 14. Missions and the daily gift

On the island, the **scroll button beside the wallet** carries a number
when something is waiting. It opens Missions: today's gift (day N of 7,
Claim), the daily missions with progress bars and Claim buttons, and the
feats. Clear a stage, summon once and claim the bazaar's daily offering,
then come back: three missions should be claimable. Claim them all and the
"Finish every mission" bonus pays a Pantheon scroll.

Send: the missions screen after a claim, and the receipt line.

## 15. Scrolls

Summon has two rows of chips now: **Pantheons** (the three banners) and
**Scrolls** (the Endless Scroll, then Unknown, Divine, Light & Dark, Fire,
Water, Wind), each chip with how many of that scroll you hold. Every
scroll draws only what its name says: a Fire Scroll gives Fire units of any
pantheon, an Unknown Scroll gives 3★ commons, a Divine Scroll never gives
less than a 4★. The bazaar's **Scrolls** section sells them — Unknown for
drachma, the rest for divinity — and the **Laurel exchange** sells two for
arena laurels. Stages drop Unknown and Mystical scrolls; the halls drop
their element's scroll.

Send: a summon from a Fire or a Light & Dark scroll, and the unit's element.

## 16. The camera

The battle camera is **fixed** now, the way Summoners War keeps it: one
three-quarter view of the whole field from the first turn to the last. A
basic attack, a special, an enemy's turn, your turn coming round — none of
them moves it. Two things do: an ultimate (a third skill such as Anubis's
Opening of the Mouth) pushes in toward the caster for a moment and comes
back, and a heavy hit shakes. The view you saw after an enemy's attack —
looking down at your own line from above — was the old close shot's
look-at left switched on when the turn changed; it cannot happen now.

If you want the old cuts and orbits back: Obelisk → More → **Sound &
camera** → Cinematic battle camera.

Send: whether the frame ever moves when it should not.

## 17. The battle HUD

Top centre is the **attack gauge**: one track, every living unit's
portrait sliding along it as its bar fills — yours above the line with a
blue ring, theirs below with a red one, gold on the unit whose turn it is.
The health bars over the figures are wider and thicker. **Tap a skill** and
its name and what it does appear above the skill row, with the target
prompt; **hold a skill** (even one that is cooling down) and a card with
its cooldown and description opens; tap anywhere to close it.

Send: whether the gauge order matches who actually moved next.

## 18. The Labyrinth

The new building on the island, right of the summoning circle. Inside:
three **relic dungeons** on top (the Vault of the Colossus, the Lair of the
Hydra, the Necropolis of the Devourer), the five **Halls of Essence** below.
Tap a dungeon: the boss (the Colossus, the Hydra, the Unwrapped King), the
sets it drops, and ten level medallions, B1 open. Tap B1 → the briefing shows three waves (W1, W2, BOSS) and "Relic
(3★) · always" with the set names → Begin. The fight is one battle: when a
wave is down the next walks on from the back and the chip beside the stage
name reads Wave 2/3, then 3/3; your health and cooldowns carry over. The
victory panel shows the relic. B2 opens when B1 falls. Levels climb hard:
B4 wants a 4★ team, B7 5★s with relics, B10 a maxed 6★ team; the Colossus
is the gentlest.

Send: whether the second wave arrived (and looked like it arrived, not
popped), what the relic was, and how B1 felt for your team.

## 19. The unit sheet and the relic picker

Collection → tap a unit. One screen, nothing to scroll: the card, level bar,
power and three buttons (Power up, Evolve, Awaken) on the left; the six
relic slots in a ring around the element in the middle, slot 1 at the top
and the rest clockwise; the stats on the right, each with its relic bonus in
green; the skills along the bottom — tap one and its words, cooldown,
estimated damage and skill-up dots show beside it. The book (top right) has
the lore; the wand auto-equips; the padlock locks.

Tap a slot. The picker: candidates on the left, best fit for the unit's role
first (tap one to select it, it does not equip yet); on the right what is in
the slot now, the pick, and **every stat before → after** with the change,
plus the sets it would complete or break. Equip, or take one off another
unit ("Take and equip"), or unequip what is there.

Send: a screenshot of the sheet and one of the picker with a pick selected,
and whether anything is cut off at the edges of your phone.

## 20. Relic power-up

Tap a **worn** slot on the unit sheet (or a relic in Collection → Relics).
The power-up screen: the relic on the left with its main stat and the value
the next level gives, its sub stats, and a track of fifteen pips with +3,
+6, +9 and +12 ringed — those are the levels that roll a sub stat — and a
crown on +15. On the right: the success rate for the next level, the cost,
and **Power up**. To +3 it always takes; from +4 the odds fall a step a
level, to 40% for +15. A success glows gold and shows what changed ("New
sub stat: SPD +4", "HP % +5% → +9%"); a failure shakes, the drachma is
gone and the level stays, exactly as the genre does it. +15 lifts the main
stat in one jump. Change, Unequip, Reappraise and Sell sit under the
button; the padlock is at the top.

Send: a screenshot after a success and after a failure, and whether the
odds felt fair for the cost.

## If it does not build

```bash
xcodebuild -project Pantheon.xcodeproj -scheme Pantheon \
  -destination 'generic/platform=iOS' build 2>&1 | tee build.log
grep -n "error:" build.log
```
Paste the `grep` output. The same build runs on GitHub on every push, so a
compile error on your Mac that CI did not see is worth a look on both sides.

## What is not done

- **Enemies are portrait sprites** by design until their meshes exist, and
  so are the Shabti.
- **Ares is untuned.** The balance sim cannot see his self-buff or his extra
  turn, so his numbers are a first guess; say whether he feels weak or wild.
- **Music is synthesised.** Two loops; real ones want Suno or Udio.
- **The island is still a painting.** Units idling on it, particles and a
  day-night cycle are the next phase (`Docs/PLAN.md`, *The road to
  Summoners War*).
- **Nothing in this build has been seen on a phone yet.** It has been seen
  compiled, tested and photographed on GitHub's simulator; the phone has the
  last word on feel, sound and the real GPU.
