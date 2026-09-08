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
[ModelLibrary] 3D files actually inside the app: 80
[ModelLibrary]   OK       anubis -> anubis.usdz
[ModelLibrary]   OK       ares -> ares.usdz
[ModelLibrary]   OK       zeus -> zeus.usdz
[ModelLibrary] 'anubis' built 1 node(s) of interest:
[ModelLibrary] model: 1 textured material(s); the 45° costume accent becomes 165° for #7FE0C8 in the surface shader
[ModelLibrary] 'anubis': 1 skinner(s) rebound to this instance's own bones
[ModelLibrary] 'anubis': measured x1.11 y2.05 z0.42, 2.1 units → 2.05 m (×0.9991)
[ModelLibrary] clip animation taken from … , 1.67 s, a group
```

- **80 files** — eight per family, eleven families less the Shabti, who have
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
  bottom; the enemies stand behind them, heads below the top row; the
  painting shows above.
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
