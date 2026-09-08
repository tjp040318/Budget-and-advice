# The plan

Written after opening the shipped `.usdz` files with Pixar's USD library rather
than guessing from screenshots, and revised after the first session in which
Meshy could be driven from this environment. The measurements below are from the
actual files and they change the answer to "can this look like Summoners War".

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
| The raw Anubis export | 197,879 |
| **What ships now** | **4,999**, plus a 1,499 `_lod` for crowded stages |

Decimation, run for real over the whole family with `python3 tools/mesh.py anubis`:

```
anubis.usdz              197,879 → 4,999 tris    22.0 → 1.6 MB   1024 texture
anubis_lod.usdz          197,879 → 1,499 tris    22.0 → 0.5 MB    512 texture
anubis_<clip>.usdz  × 6  197,879 → 1,499 tris    21.9 → 0.1–0.2 MB each, 128 texture
                                                153.5 → 3.0 MB in the app bundle, 9 s
```

Skin weights carry across by nearest-neighbour remapping from the source
vertices, and every output was re-read with USD afterwards: 24 joints, every
animation frame, weights renormalised, UVs and material binding intact. The
per-clip files are cut harder because `ModelLibrary` only lifts the animation
out of them; their geometry is read once and discarded.

The untouched exports now live in `Art/Models/`, outside the folder Xcode
synchronises into the app. Moving them cost the repository nothing — same
blobs — and the bundle 151 MB.

---

## Recommendation: stay on iOS/SceneKit

This reverses what I said earlier, and the reason is the measurements above.

The case for Unity was its tooling — a scene editor, an asset pipeline, a way to
handle models without a DCC package. But the model pipeline turns out to be
scriptable end to end: generating, rigging, animating, converting, normalising,
decimating and re-exporting all work from Python. That was the main thing the
move was buying.

What remains true about Unity: better particle and animation tooling, and an
asset store with rigged monster packs. Worth revisiting **at around ten
characters**, if authoring becomes the bottleneck. Not worth weeks of rewrite
today against a game that already runs on the phone.

The island is the one thing that argued for a scene editor, and it does not need
one — see phase 3.

---

## The character pipeline, end to end

`api.meshy.ai` is reachable from this environment and a `MESHY_API_KEY` is
provisioned, which removes the one step the previous plan said needed a person
at a keyboard. Four commands take a character from a sentence to the bundle:

```bash
python3 tools/meshy.py generate sekhmet --height 2.0 --prompt "..." --negative "..."
python3 tools/meshy.py download sekhmet      # -> Art/Models/sekhmet*.glb
python3 tools/glb2usd.py sekhmet             # -> Art/Models/sekhmet*.usdz
python3 tools/mesh.py sekhmet                # -> Pantheon/Resources/Models/, decimated
```

`generate` runs text-to-3D preview, refine, rigging and one animation task per
clip, and records every task id in `Art/Models/<asset>.meshy.json` before it
waits, so a re-run resumes rather than paying again. Measured on Sekhmet:

| Stage | Credits | Wall clock | Output formats |
|---|---|---|---|
| preview | 20 | ~1.5 min | glb fbx obj stl **usdz** |
| refine (textures, PBR) | 10 | ~1.5 min | the above + base colour, metallic, roughness, normal maps |
| rig at 2.0 m | 5 | ~3 min | glb fbx only |
| six battle clips | 3 each | ~2 min, in parallel | glb fbx only |
| **one character** | **53** | **~12 min** | |

Only the unrigged stages return USDZ, hence `glb2usd.py`. It writes the same
prim layout as the Blender exports that already load in the game, verified on
three Khronos sample rigs by re-skinning the written file in numpy.

The balance was 1,186 credits before Sekhmet and 1,133 after: roughly twenty
more characters at this rate.

**What is still closed.** `assets.meshy.ai`, where the finished files are
served from, is refused by the environment's network policy, so `download`
could not run. The tasks are done and waiting; nothing is lost. Adding the host
is step 1 below.

---

## Phases

### Phase 0 — make the current build correct *(in progress)*

- [x] Cut-out sprites for enemies, correct scale and aspect
- [x] Mirror floor reflection removed
- [x] Painted panel no longer swamps small plates
- [x] Model scale/centre/orientation normalised from measured bounds
- [x] Decimated models in the bundle (above)
- [ ] **Confirm on device.** Needs the `[ModelLibrary] 'anubis':` console line.
  The bundle now holds 8 model files (the `_lod` is new); Sekhmet shows a
  grey dot and letter plates until her files land, which is correct.

### Phase 1 — the model pipeline *(done)*

Run in anger and measured above. The pipeline is `Art/Models` → `mesh.py` →
`Pantheon/Resources/Models`, one command per family.

### Phase 2 — a second and third character family *(Sekhmet: code and model done, art pending)*

Per family: a kit, a balance pass, five portraits, one mesh through Meshy, and
the pipeline above.

- **Sekhmet** — Ember bruiser, the roster's first damage archetype. Every
  variant's Eye of Ra breaks defence; the claws Burn, Slow, Glance, weaken or
  make unrecoverable depending on the element. Natural 5★, which also fills
  the gacha's 5★ tier for the first time.
  - [x] Kit, five variants, in `UnitDatabase.swift`; in the summon pool
  - [x] Balance model updated; the duel against Anubis sits at 81–88% for her
  - [x] Model, rig and six clips generated (task ids in the manifest)
  - [ ] Download, convert, decimate — needs `assets.meshy.ai` (step 1)
  - [ ] Five portraits — needs `GEMINI_API_KEY` in the environment (step 2);
    the prompt is in `Docs/ART_2D.md`
- **Thoth** — Radiance support, a cleanse and an attack-bar push. Gives the
  roster its first real control archetype. Next.

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

## What to do next

1. **Open the download host.** claude.ai/code → cloud icon above the message
   box → hover the environment → gear → **Network access: Custom** → add
   `assets.meshy.ai` (and `cdn.meshy.ai`, for animation previews) beside
   `api.meshy.ai` → keep **"Also include default list of common package
   managers"** ticked → save. New sessions only.
2. **Add the Gemini key** in the same dialog under **API credentials** as
   `GEMINI_API_KEY`. That opens the host and keeps the key out of the session.
3. **Start a new session** and ask for: download, convert and decimate Sekhmet,
   then the five portraits. The commands are the four above plus
   `tools/genart.py` per `Docs/ART_2D.md`; ~15 minutes.
4. **Run on device** and paste the `[ModelLibrary]` block from the console.
   Both the decimated Anubis and, after step 3, Sekhmet are unconfirmed there.

---

## What I can and cannot do

| | |
|---|---|
| 2D art at volume | ✅ 29 assets in ~40 min, proven — when a Gemini key is present |
| Sound effects | ✅ synthesised, in the repo |
| Read, normalise, decimate, re-export 3D | ✅ proven on the whole Anubis family |
| **Generate, rig and animate a 3D character** | ✅ **proven: Sekhmet, 53 credits, 12 minutes** |
| Convert Meshy's rigged GLB to USDZ | ✅ written and verified on sample rigs; not yet on a Meshy file |
| Fetch the finished files | ❌ until `assets.meshy.ai` is on the allow-list |
| All code, logic, balance, integration | ✅ |
| Compile or see the running app | ❌ — the reason bugs still reach your phone |

The 3D bottleneck is gone in principle: one command per character, a quarter
of an hour, two dollars of credits. What remains is one network setting and one
key, both a minute each in the environment dialog.
