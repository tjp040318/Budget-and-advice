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

## What the second look found

The first build with those files loaded Anubis as a scatter of gold shards. The
files were re-read with USD and skinned in numpy, and five things were wrong
with the export, none of them with the game:

1. The armature's centimetre-to-metre scale existed only as a time sample, with
   no default value, so at rest the file described a 170-unit figure.
2. The skeleton's rest pose was not its bind pose: the hips sat 68 units to
   one side and twisted 40°, so the un-animated model — what the summon stage
   shows — stood somewhere else.
3. The mesh was Y-up data tilted 90° by its own node inside a Z-up stage, with
   the same tilt repeated in `geomBindTransform`.
4. Every vertex carried ten bone influences, padded from a mean of three.
   Model I/O's skinning attributes are four wide; a reader that assumes four
   mis-strides the array and glues vertices to random bones, which is what
   shards are.
5. The clips carried horizontal root motion — the combat idle started 49 cm off
   the slot — and floated 5–13 cm above the ground.

Reading the clips frame by frame turned up two more: the hit reaction was a
knock-up with no flinch in it (airborne by frame three, on his back by frame
twenty-one), and the attacks ran 2.5–3.9 s against the second or so the engine
allows a hit. The tool now synthesises a flinch from the combat idle when the
exported reaction is a fall, and the game plays one-shot clips at the contract's
pace.

So the pipeline now writes a **canonical** file (`tools/character.py`): Y-up,
metres, feet on the origin, facing +Z, rest = bind, four influences, root
locked and grounded, every prim named once. The loader was given a matching
belt-and-braces step — a cloned skinner is rebound to its own bones — and it
logs the bounding box and skinner it actually built, so the next console paste
settles what SceneKit does with a clean file.

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
python3 tools/mesh.py sekhmet                # -> Pantheon/Resources/Models/, canonical and decimated
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

Only the unrigged stages return USDZ; `mesh.py` reads the GLB directly and
writes the canonical file described above, verified on three Khronos sample
rigs and on the whole Anubis family by re-skinning the written files in numpy.

The balance was 1,186 credits before Sekhmet, 1,133 after her and 1,080 after
Zeus: roughly twenty more characters at this rate.

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
- [x] Battle camera solved for a portrait phone: both lines in the clear band,
  a finite stage that fades into the painting, the painting cropped to the
  screen rather than stretched over it
- [x] Portraits, the summon stage, the island, an app icon; the gacha only
  produces characters whose art has shipped
- [ ] **Confirm on device.** Needs the `[ModelLibrary] 'anubis':` console line.
  The bundle now holds 8 model files (the `_lod` is new); Sekhmet shows a
  grey dot and letter plates until her files land, which is correct.

### Phase 1 — the model pipeline *(done)*

Run in anger and measured above. The pipeline is `Art/Models` → `mesh.py` →
`Pantheon/Resources/Models`, one command per family.

### Phase 2 — a second and third character family *(Sekhmet and Zeus: code and models done, art pending)*

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
- **Zeus** — Greek, the roster's control archetype and the first unit outside
  Egypt. Every variant's Thunderclap hits the enemy line and takes its turn
  away (stun, freeze, sleep, attack-bar knockback, provoke); the Keraunos
  ignores 40% of defence and hands the team a buff; the awakened passive
  pushes the team's attack bar at the start of battle. Natural 5★.
  - [x] Kit, five variants, in `UnitDatabase.swift`; in the summon pool behind
    the art gate, with an "Olympus Stirs" banner that appears with his portraits
  - [x] Balance model updated (stun and area-skill valuation added); he beats
    Anubis 66–82% and loses to Sekhmet, which is the intended shape
  - [x] Model, rig and six clips generated (task ids in `Art/Models/zeus.meshy.json`)
  - [x] Forked-lightning effects for all three skills (`VFXLibrary`), the sky
    flashes with them, and a synthesised thunder crack (`thunder.wav`)
  - [ ] Download, convert, decimate — needs `assets.meshy.ai` (step 1)
  - [ ] Five portraits — needs `GEMINI_API_KEY` in the environment (step 2);
    the prompt is in `Docs/ART_2D.md`
- **Thoth** — Radiance support, a cleanse and an attack-bar push, so the
  Egyptians have a second support. Next.

### Phase 3 — the island *(built; the painting is a stand-in)*

Summoners War's town is not a 3D scene the player navigates. It is a painted
backdrop with a fixed camera and tappable hotspots. That is what `IslandView`
is: the app now opens on it.

- [x] `Landmark` model — title, anchor in the painting, unlock level,
  destination, upgrade tiers — and five landmarks in `IslandDatabase`
- [x] Tap targets mapped through the painting's aspect-fill frame, a glow on
  anything actionable (energy, scrolls, arena attacks), a count badge, a tier
  mark, locked state with a shake
- [x] A 1536 × 2048 backdrop — painted procedurally by `tools/island.py` so
  the screen has a horizon today
- [ ] The real painting: one Gemini prompt, in `Docs/ART_2D.md` §6, once the
  key is in the environment
- [ ] Upgrade states of the buildings: a second and third painting per tier

### Phase 4 — sound and feel

- **Music.** Two synthesised loops are in — an island loop of pads, a drone
  and a plucked melody in E Phrygian dominant, and a 96 BPM battle loop with
  a kick, a frame drum, a bass ostinato and chord stabs (`tools/music.py`).
  Stand-ins, but stand-ins that set a mood. Suno or Udio for the real ones:
  a battle loop, a town loop, a summon sting. ~$10 for a month.
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
3. **Pull, build, run** and send two things: the `[ModelLibrary]` block from
   the console (`Docs/PLAYTEST.md` §1 says what each line means) and a
   screenshot of Reed Fields. That paste is what decides whether the canonical
   file is enough or SceneKit's importer needs a further workaround.
4. **In a new session**, ask for Sekhmet and Zeus downloaded and built, the
   ten portraits, and the island painting — `Docs/ART_2D.md` §1 and §6 have the
   prompts; about half an hour together.

---

## What I can and cannot do

| | |
|---|---|
| 2D art at volume | ✅ 29 assets in ~40 min, proven — when a Gemini key is present |
| Sound effects | ✅ synthesised, in the repo |
| Read, normalise, decimate, re-export 3D | ✅ proven on the whole Anubis family |
| **Generate, rig and animate a 3D character** | ✅ **proven twice: Sekhmet and Zeus, 53 credits and ~12 minutes each** |
| Convert Meshy's rigged GLB to USDZ | ✅ written and verified on sample rigs; not yet on a Meshy file |
| Fetch the finished files | ❌ until `assets.meshy.ai` is on the allow-list |
| All code, logic, balance, integration | ✅ |
| Compile or see the running app | ❌ — the reason bugs still reach your phone |

The 3D bottleneck is gone in principle: one command per character, a quarter
of an hour, two dollars of credits. What remains is one network setting and one
key, both a minute each in the environment dialog.
