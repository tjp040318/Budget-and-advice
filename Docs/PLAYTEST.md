# Playtest checklist

What to look at on device, in order, and what to send back. Each item says what
"right" looks like so a wrong one is obvious.

```bash
cd ~/Pantheon && git pull
```
Then **⌘R** in Xcode with the console open (**⌘⇧C**).

## 1. Console, first ten lines

Look for these two blocks near the top:

```
[ModelLibrary] 3D files actually inside the app: 7
[ModelLibrary]   OK       anubis -> anubis.usdz
[ModelLibrary] 'anubis': Z-up export (x… y… z…) — pitched -90°, feet lifted 0.00 m
```

- **`already Y-up`** or **`pitched`/`rolled`** — either is fine as long as Anubis
  stands up in step 3. If he is on his side or upside-down, paste the line.
- **`MISSING anubis`** — the model is not in the bundle; paste the whole block.
- **`SceneKit could not open it`** — the export is unreadable; paste the error.

## 2. Collection

- Every card is a **painted portrait** — no letters on gradients anywhere.
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
- Anubis is the real model, upright.
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
- **3D assets** lists Anubis green, everyone else grey — grey means "portrait
  sprite", which is expected today.

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
- **One character family.** The gacha pool is five Anubis; the next family
  needs a kit, a balance pass and portraits — `tools/genart.py` makes the
  portraits in minutes.
- **Kill slow-motion** is the longest freeze plus the heaviest shake; SceneKit
  has no global time-scale.
