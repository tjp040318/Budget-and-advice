# Playtest checklist

What to look at on device, in order, and what to send back. Each item says what
"right" looks like so a wrong one is obvious.

```bash
cd ~/Pantheon && git pull
```
Then **⌘R** in Xcode with the console open (**⌘⇧C**).

## 0. The island

The app opens on it. Five plaques on a painted island; the ones with something
to do glow. Tap **Gate of the Duat** and the Campaign tab opens; tap **Summoning
Circle** and Summon opens. The header shows your name, level and wallet.

Send: a screenshot.

## 1. Console, the `[ModelLibrary]` lines

Look for this block, printed the first time Anubis is loaded:

```
[ModelLibrary] 3D files actually inside the app: 8
[ModelLibrary]   OK       anubis -> anubis.usdz
[ModelLibrary] 'anubis' built 3 node(s) of interest:
      anubis_mesh: geometry … bbox x -0.59..0.59 y 0.00..2.05 z -0.21..0.21; skinner with 24 bones
[ModelLibrary] 'anubis': 1 skinner(s) rebound to this instance's own bones
[ModelLibrary] 'anubis': measured x1.18 y2.05 z0.41, 2.05 units → 2.05 m (×1.0000)
[ModelLibrary] clip animation taken from … , 1.67 s, a group
```

- **`y 0.00..2.05` and `×1.0000`** — the file is canonical and the game did
  nothing to it, which is the intent.
- **`skinner with 24 bones`** missing — SceneKit did not build a skinned mesh;
  paste the block.
- **`clip animation taken from Hips`** or **`a single track`** — the loader
  picked one joint's track instead of the clip; paste the block.
- **`MISSING anubis`** — the model is not in the bundle; paste the whole block.
- **`SceneKit could not open it`** — the export is unreadable; paste the error.

## 2. Collection

- Every Anubis card is a **painted portrait**. Sekhmet's five are letters on
  gradients until her portraits land; nothing else should be.
- The card frame is **carved metal**, gold for 4★ Anubis. Corners overlap the
  art slightly; that is intentional.
- Tap a unit: the detail screen opens.

Send: one screenshot of the grid.

## 3. Summon

- The banner is painted (Anubis rising from a gate).
- Pull once. The reveal should go: **dark charge → white flash → figure springs
  in → stars tick in one at a time (feel the haptic on each) → name slams down
  → details fade in**. About three seconds for a 4★.
- The figure: **standing upright, filling most of the stage, slowly turning**,
  on a rotating tinted disc. Not lying down, not tiny, not chrome.
- Tap during the sequence: it completes instantly. Tap after: next result.
- Sound: a rising charge, a burst on the flash, a tick per star.

Send: a screenshot at the moment the name is on screen.

## 4. Battle (Campaign → The First Gate)

- Backdrop is a **painted gate at dusk**, not a coloured void.
- Enemies are **portrait cards standing in the world** with a shadow and an
  element glow — not green capsule figures. They bob, lunge and tilt.
- Anubis is the real model: upright, feet on the ground ring, about the same
  height as the enemy sprites, **breathing in a combat stance** rather than
  standing frozen in an A-pose. Attacks play the swing, a death lies down and
  stays down. Every hit on him currently plays a knock-up that throws him in
  the air — that is the clip that was exported, not a bug; see
  `Docs/ART_PIPELINE.md`.
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
- **3D assets** lists Anubis green, everyone else grey — Sekhmet included,
  until her model lands. Grey means "placeholder", which is expected today.

## If it does not build

```bash
xcodebuild -project Pantheon.xcodeproj -scheme Pantheon \
  -destination 'generic/platform=iOS' build 2>&1 | tee build.log
grep -n "error:" build.log
```
Paste the `grep` output. Everything since the last successful build was written
without a compiler and has been reviewed, not compiled.

## What is not done

- **Only Anubis has a 3D model.** Enemies are portrait sprites by design until
  their meshes exist — `Docs/ART_PIPELINE.md` for the Meshy route.
- **No music.** Effects only; the generator does not make music.
- **Sekhmet has no art in the bundle yet.** Her five variants are in the gacha
  pool (they are its 5★ tier) and render as letter plates over a placeholder
  rig. The model is generated and waiting on a download, the portraits on a
  Gemini key — `Docs/PLAN.md`, *What to do next*.
- **Kill slow-motion** is the longest freeze plus the heaviest shake; SceneKit
  has no global time-scale.
