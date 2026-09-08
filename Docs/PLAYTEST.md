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
[ModelLibrary] 3D files actually inside the app: 24
[ModelLibrary]   OK       anubis -> anubis.usdz
[ModelLibrary]   OK       sekhmet -> sekhmet.usdz
[ModelLibrary]   OK       zeus -> zeus.usdz
[ModelLibrary] 'anubis' built 3 node(s) of interest:
      anubis_mesh: geometry … bbox x -0.59..0.59 y 0.00..2.05 z -0.21..0.21; skinner with 24 bones
[ModelLibrary] 'anubis': 1 skinner(s) rebound to this instance's own bones
[ModelLibrary] 'anubis': measured x1.18 y2.05 z0.41, 2.05 units → 2.05 m (×1.0000)
[ModelLibrary] clip animation taken from … , 1.67 s, a group
```

- **24 files** — eight per family (the Shabti have no models by design).
- **`y 0.00..2.05` and `×1.0000`** — the file is canonical and the game did
  nothing to it. Sekhmet reads `y 0.00..2.00`, Zeus `y 0.00..2.15`.
- **`clip animation taken from …, a group`** is the good case. **`assembled
  from N joint tracks`** means the importer split the clip and the loader
  stitched it; also fine, and worth knowing. **`a single track`** means the
  fix did not engage; paste the block.
- **`MISSING`** or **`could not open it`** — paste the whole block.

## 2. Collection

- **Every card is a painted portrait**: Anubis faces left, Sekhmet (lioness,
  sun disc) faces right, Zeus (white beard, laurel, lightning) faces you, and
  the Shabti (a cracked stone figurine, arms crossed) in five colours. A
  letter on a gradient anywhere means a filename is wrong; say which card.
- Six or more cards across, the grid fills the width.
- **Train** at the top left opens the Hall of Ka.
- Tap a unit: the detail screen opens.

Send: one screenshot of the grid.

## 3. Unit detail — Overview

- Every stat shows its **base** number and, when relics are equipped, a
  **green +N** beside it. Equip or remove a relic on the Relics tab and come
  back: the green number changes, the base does not.

## 4. Summon

- Two painted banners: **The Duat Opens** and **Olympus Stirs**.
- Pull ten. Most are **Shabti** now — the common tier — in mixed elements;
  an Anubis is a 4★ and **shows four stars** on the reveal; a Sekhmet or Zeus
  is 5★. Ten identical fire Anubis is the old bug; say so if you see it.
- The reveal: **dark charge → white flash → figure springs in on the left,
  slowly turning → stars tick in on the right → name slams down → details
  fade in**. Sekhmet should be a gold and red lioness you can look at, not a
  white silhouette. A grey dot or a letter plate in place of a figure means
  the model did not load — paste the console block.
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
- Locked units never appear as fodder.

Send: a screenshot of the Result panel before you tap Power up.

## 6. Battle (Campaign → Reed Fields), with Sekhmet or Zeus on the team

- **Landscape framing**: one row across the top (flag, stage name, the turn
  order faces, AUTO, ×1, log), an open middle, and a bottom bar with the
  actor's plate at the left and the skill buttons at the right. Your line
  stands in the open middle, about a third of the screen tall, feet near the
  bottom; the enemies stand behind them, heads below the top row; the
  painting shows above.
- **Textures**: Anubis has a black jackal head, a gold and lapis collar and a
  white kilt. Marbled tan bands mean the old file is still in the build.
- **Look**: every model has a thin edge of light in its element's colour,
  lifted shadows with a painted two-tone feel, and its costume in the
  element's colour — a tide Anubis wears blue where the ember one wears
  orange, with the fur and skin unchanged. Say if anything looks flat, or
  if a colour landed on skin.
- **Idle**: the units breathe in a combat stance from the first second.
  Arms straight out and legs straight is the A-pose; it was a one-line bug
  in the battle unit and should be gone. If you see it, paste the console
  block.
- Sekhmet and Zeus stand the same way, a little taller than Anubis. Zeus's
  Thunderclap puts forked lightning across the enemy line and cracks.
- Attack. On the hit: freeze, shake, tap, an oversized number, a thud.

Send: a screenshot mid-battle, and a sentence on whether the framing feels
like a game or like a diorama seen from a ladder.

## 7. More

- **Diagnostics** → the console, Copy all, Share.
- **3D assets** → Anubis, Sekhmet and Zeus green; the Shabti and the enemies
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
- **Music is synthesised.** Two loops; real ones want Suno or Udio.
- **The island is still a painting.** Units idling on it, particles and a
  day-night cycle are the next phase (`Docs/PLAN.md`, *The road to
  Summoners War*).
- **Nothing in this build has been seen on a phone yet.** It has been seen
  compiled, tested and photographed on GitHub's simulator; the phone has the
  last word on feel, sound and the real GPU.
