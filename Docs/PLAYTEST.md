# Playtest checklist

What to look at on device, in order, and what to send back. Each item says what
"right" looks like so a wrong one is obvious.

```bash
cd ~/Pantheon && git pull
```
Then **⌘R** in Xcode with the console open (**⌘⇧C**).

## 0. The island

The app opens on it: a painted island at dusk, sun at the upper right, and
five plaques that should each sit **on its building** — the pillared hall at
the upper left, the obelisk at the upper right (plaque under the shaft, not
across it), the ring of pillars around the pool in the middle, the twin-pylon
gate at the lower left, the oval arena at the lower right. Nothing should be
cut off by the screen edge; the painting was composed for a phone's crop. The
ones with something to do glow. Tap **Gate of the Duat** and the Campaign tab
opens; tap **Summoning Circle** and Summon opens. The header shows your name,
level and wallet. A pad loop plays underneath; it changes to drums when a
battle starts and back when it ends. **More → Sound** has a Music toggle if
you would rather not.

Send: a screenshot. If a plaque is off its building, say which and which way.

## 1. Console, the `[ModelLibrary]` lines

Look for this block, printed the first time a model is loaded:

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

and the same again for Sekhmet and Zeus the first time each appears, whose
files say:

```
      sekhmet_mesh: … bbox x -0.33..0.33 y 0.00..2.00 z -0.20..0.20; skinner with 24 bones
      zeus_mesh:    … bbox x -0.67..0.67 y 0.00..2.15 z -0.32..0.32; skinner with 24 bones
```

- **24 files** — eight per family. Fewer means a family did not copy in.
- **`y 0.00..2.05` and `×1.0000`** — the file is canonical and the game did
  nothing to it, which is the intent. Sekhmet should read `y 0.00..2.00`,
  Zeus `y 0.00..2.15`.
- **`skinner with 24 bones`** missing — SceneKit did not build a skinned mesh;
  paste the block.
- **`clip animation taken from Hips`** or **`a single track`** — the loader
  picked one joint's track instead of the clip; paste the block.
- **`MISSING anubis`** — the model is not in the bundle; paste the whole block.
- **`SceneKit could not open it`** — the export is unreadable; paste the error.

## 2. Collection

- **Every card is a painted portrait** now: Anubis faces left, Sekhmet (a
  lioness with a sun disc) faces right, Zeus (white beard, laurel, lightning)
  faces you. Five colourways each, the same character in each. A letter on a
  gradient anywhere means a filename is wrong; say which card.
- The card frame is **carved metal**: the violet epic frame on 4★ Anubis, the
  gold legendary frame on 5★ Sekhmet and Zeus. Corners overlap the art
  slightly; that is intentional.
- Tap a unit: the detail screen opens.

Send: one screenshot of the grid.

## 3. Summon

- Two painted banners now: **The Duat Opens** (Anubis rising from a gate) and
  **Olympus Stirs** (Zeus, arms spread, over a storm). The second one appears
  because Zeus's portraits are in the bundle; if it is missing, the portraits
  did not copy in.
- Pull on Olympus Stirs until a 5★ lands (3% a pull, hard pity at 90; about
  30 pulls on average). The reveal should go: **dark charge → white flash →
  figure springs in → stars tick in one at a time (feel the haptic on each) →
  name slams down → details fade in**. About three seconds for a 4★, five
  stars for Sekhmet or Zeus.
- The figure: **standing upright, filling most of the stage, slowly turning**,
  on a rotating tinted disc. Not lying down, not tiny, not chrome. Sekhmet is
  a 2 m lioness-headed woman, Zeus a 2.15 m bearded man; a grey dot or a
  letter plate in their place means the model did not load — paste the
  console block.
- Tap during the sequence: it completes instantly. Tap after: next result.
- Sound: a rising charge, a burst on the flash, a tick per star.

Send: a screenshot at the moment the name is on screen.

## 4. Battle (Campaign → The First Gate)

- Backdrop is a **painted gate at dusk**, not a coloured void.
- Enemies are **portrait cards standing in the world** with a shadow and an
  element glow — not green capsule figures. They bob, lunge and tilt.
- The framing: enemies in the upper half standing against the painting, your
  team in the lower half above the command panel, nobody cut off by the edge
  of the screen. The stage is a platform that fades into the backdrop.
- Anubis is the real model: upright, feet on the ground ring, about the same
  height as the enemy sprites, **breathing in a combat stance** rather than
  standing frozen in an A-pose. He faces the enemies, so you see his back and
  shoulders; the enemies face you. Attacks play the swing at fighting pace, a hit
  makes him flinch back for under half a second, a death lies down and stays
  down.
- **Put Sekhmet or Zeus on the team** (Collection → team) and fight again.
  Both should stand the same way: feet on the ring, facing the enemies, a
  little taller than Anubis. Their hit reaction is a crouch-and-recover, not
  a fall; their death is a fall that stays down. Zeus's Thunderclap should
  put forked lightning across the enemy line, flash the sky and crack. If
  either is huge, tiny, lying down, in an A-pose or in pieces, that is the
  importer disagreeing with the file — paste the console block and a
  screenshot; the file itself verifies at the right size.
- Turn-order strip shows **faces**, not letters. The actor plate at the bottom
  shows the actor's face.
- Attack. On the hit: the world **freezes for a frame or two**, the camera
  **shakes**, the phone **taps**, the number **pops in oversized and settles**,
  and there is a **thud**. A crit does all of that harder with a gold number.
- ×2 speed: everything is still there, snappier. Skip: none of it.
- Win: a three-note fanfare and a success haptic.

Send: a screenshot mid-hit if you can catch one, and a sentence on whether the
freeze and shake feel right or too much.

## 5. More

- **Sound** toggle turns effects off and on (a chime confirms on).
- **3D assets** lists Anubis, Sekhmet and Zeus green; the enemies grey. Grey
  means "placeholder", which is expected for enemies.

## If it does not build

```bash
xcodebuild -project Pantheon.xcodeproj -scheme Pantheon \
  -destination 'generic/platform=iOS' build 2>&1 | tee build.log
grep -n "error:" build.log
```
Paste the `grep` output. Everything since the last successful build was written
without a compiler and has been reviewed, not compiled.

## What is not done

- **Enemies are portrait sprites** by design until their meshes exist — the
  three player families are the only real models. `tools/meshy.py` is the
  route; each is an hour and 53 credits.
- **Music is synthesised.** Two loops from `tools/music.py`; real ones want
  Suno or Udio.
- **Nothing 3D has been seen on a phone since the canonical rewrite**, and
  Sekhmet and Zeus never. Every file verifies in numpy; the phone has the
  last word.
- **Kill slow-motion** is the longest freeze plus the heaviest shake; SceneKit
  has no global time-scale.
