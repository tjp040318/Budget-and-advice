# The plan

Written after opening the shipped `.usdz` files with Pixar's USD library rather
than guessing from screenshots. The measurements below are from the actual
files and they change the answer to "can this look like Summoners War".

---

## What the files actually say

```
anubis.usdz     upAxis Z    197,879 triangles    98,947 vertices
                24-joint humanoid rig (Hips/LeftUpLeg/… — Mixamo naming)
                skin weights present, 10 influences per vertex
                155 frames of animation at 30fps
                bounding box 212 × 212 × 320 units, metersPerUnit = 1.0
                origin ~1/3 up the torso, ~100 units off centre
```

Two findings matter.

**The render bug was scale, not orientation.** The game asks for a 2.05 m
character; the file describes a 320 m one standing 100 m off the origin. A
camera framing two metres of world therefore showed an arbitrary slice of the
model's shin. No amount of rotating it could have fixed that, which is why two
attempts at orientation did not. `ModelOrientation.normalise` now measures the
model and scales, centres and grounds it.

**Every animation clip is real.** 46 to 155 frames each. The motion was always
there; nothing could play it at that scale.

## Polygons: the actual comparison

| | triangles |
|---|---|
| Summoners War monster (2014, mobile) | ~2,000–5,000 |
| **This Anubis export** | **197,879** |
| What ten of them cost on screen | ~2M — far beyond a phone's budget for characters |

Decimation, measured on this exact mesh:

```
197,879 → 11,999 tris    0.3 s
197,879 →  4,999 tris    0.2 s
197,879 →  2,999 tris    0.2 s
```

So the answer to "can we build characters the way they did" is **yes, and it is
seconds of work per model, not hours.** The heavy Meshy export becomes the
authoring source; the game ships a decimated copy. Skin weights carry across by
nearest-neighbour remapping from the source vertices, which is standard practice
and holds well at these ratios.

Expected effect on this repo: **154 MB of models → under 10 MB**, and ten
characters on screen at ~50k triangles total, which any iPhone renders without
noticing.

---

## Recommendation: stay on iOS/SceneKit

This reverses what I said earlier today, and the reason is the measurements
above.

The case for Unity was its tooling — a scene editor, an asset pipeline, a way to
handle models without a DCC package. But the model pipeline turns out to be
scriptable end to end: reading, normalising, decimating and re-exporting all
work from Python against the USD files directly. That was the main thing the
move was buying.

What remains true about Unity: better particle and animation tooling, and an
asset store with rigged monster packs. Worth revisiting **at around ten
characters**, if authoring becomes the bottleneck. Not worth weeks of rewrite
today against a game that already runs on the phone.

The island is the one thing that argued for a scene editor, and it does not need
one — see phase 3.

---

## Phases

### Phase 0 — make the current build correct *(in progress)*

- [x] Cut-out sprites for enemies, correct scale and aspect
- [x] Mirror floor reflection removed
- [x] Painted panel no longer swamps small plates
- [x] Model scale/centre/orientation normalised from measured bounds
- [ ] **Confirm on device.** Needs the `[ModelLibrary] 'anubis':` console line.

### Phase 1 — the model pipeline *(written, not yet run in anger)*

`tools/mesh.py` exists and its read-only `--inspect` path works. The
decimating path has not been run yet — that is the next command:

```bash
python3 tools/mesh.py Pantheon/Resources/Models/anubis.usdz --tris 5000 --lod 1500
```

It keeps the untouched export beside the result as `anubis.orig.usdz`, so a
bad reduction costs nothing. What it does, once per character:

1. Open the Meshy export with USD.
2. Decimate to a target triangle budget — **5,000 for a hero, 3,000 for a
   trash mob**, matching the genre's actual numbers.
3. Remap skin weights from the source mesh by nearest neighbour.
4. Downsample textures to 1024 (2048 buys texel density a phone cannot resolve
   at the size these are drawn).
5. Re-export, and emit `<asset>_lod.usdz` at 1,500 triangles for crowded 5v5s —
   the loader already looks for it.
6. Report before/after triangles and bytes so a bad reduction is visible.

Then re-run it over Anubis and check the repo drops from 154 MB.

### Phase 2 — a second and third character family *(the real work)*

The game is a mirror match against itself until there is a second family. Per
family: a kit, a balance pass, five portraits, one mesh through Meshy, and the
pipeline above.

Suggested next two, chosen so the roster teaches the element wheel:

- **Sekhmet** — Ember bruiser, a defence-break and a bleed. Gives the roster its
  first real damage archetype.
- **Thoth** — Radiance support, a cleanse and an attack-bar push. Gives it its
  first real control archetype.

I generate the portraits; you drive Meshy for the mesh. **This is the only step
that needs you at a keyboard**, and it is the reason the roster grows slowly.

### Phase 3 — the island

Summoners War's town is not a 3D scene the player navigates. It is a painted
backdrop with a fixed camera and tappable hotspots, plus a handful of simple
props. That is a **SwiftUI screen over a painted image**, not a 3D level:

1. One 2048 × 2048 painted island (Gemini, one prompt).
2. A `Landmark` model — name, normalised rect, unlock level, destination.
3. Tap targets over the image, a glow on anything actionable, a level badge.
4. Buildings that upgrade: swap in a second painted state per level tier.

Two days, most of it art, and it looks the part immediately.

### Phase 4 — sound and feel

- **Music.** The one genuine gap. Suno or Udio: a battle loop, a town loop, a
  summon sting. ~$10 for a month, an afternoon of prompting.
- **Voice.** ElevenLabs, one summon line per character. Cheap and very genre.
- Retune `Juice.profile` once there is real animation to sync against.

### Phase 5 — content and ship

Arena rating curve, a second campaign chapter, daily energy, then TestFlight.

---

## What I can and cannot do

| | |
|---|---|
| 2D art at volume | ✅ 29 assets in ~40 min, proven |
| Sound effects | ✅ synthesised, in the repo |
| **Read, normalise, decimate, re-export 3D** | ✅ **proven on this mesh** |
| All code, logic, balance, integration | ✅ |
| **Generate a 3D model from nothing** | ❌ Meshy/Tripo/Rodin all blocked by egress policy |
| **Rig or author animation** | ❌ Meshy does both; you drive it |
| Compile or see the running app | ❌ — the reason bugs still reach your phone |

The 3D bottleneck is narrower than it looked. It is not "can we do 3D" — it is
one browser session per character to get a rigged mesh out of Meshy. Everything
either side of that is scriptable.
