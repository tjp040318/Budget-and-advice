# The plan

Written after opening the shipped `.usdz` files with Pixar's USD library rather
than guessing from screenshots, revised after the first session in which Meshy
could be driven from this environment, and again after the session in which
its files could finally be fetched and both new families were built and
painted. The measurements below are from the actual files and they change the
answer to "can this look like Summoners War".

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

## What the third look found: Meshy's GLB

The first Meshy file through the pipeline verified at **190 metres tall** in
every animated frame. The verify step exists for exactly this, and it caught it
before the phone did. The cause was a convention, not a corruption:

1. Meshy's rigged GLB (a Blender export) parents the mesh to an `Armature`
   node scaled 0.01 — the joints are in centimetres — while the vertices are
   already in metres. glTF says a skinned mesh node's own transform is
   ignored, so which frame the vertices were authored in is the exporter's
   choice: the world for Blender, the mesh node's frame for the older Khronos
   samples, an ancestor's for `RiggedSimple`. The reader assumed the mesh
   node's frame, read a 2 cm figure, and scaled the skeleton by a hundred to
   compensate. It now recovers the frame from the joints themselves (inverse
   bind × rest world is one matrix, the same for every joint when rest equals
   bind) and only falls back to assuming when they disagree. Verified on all
   five Khronos rigs, which between them use three conventions, and on both
   families.
2. The material wires the **base colour into emission at full strength**. The
   game deliberately keeps an export's emissive map (glowing runes are
   authored), so shipped as-is both characters would have rendered self-lit
   and flat. An emissive that is the base colour image is dropped.
3. Meshy's "Hit Reaction" clip is a real flinch — hips sink 8 cm, the head
   rocks 10 cm, feet stay planted, the pose recovers — so it ships as
   exported. Anubis's remains the synthesised one.

## What the fourth look found: the seams

The first screenshot of a canonical file on a phone showed Anubis at the
right size, on the ground, facing the enemies — and wrapped in marbled tan
bands with no black head, no gold collar and no white kilt. A software
renderer written for the purpose (`tools/preview.py`: a numpy rasteriser
that samples the file's own texture through its own UVs) showed the same
bands, so the fault was in the file, and the file said why:

- **The reader collapsed seams.** Blender writes texture coordinates per
  face-corner; the reader kept the first coordinate it met for each point.
  17,024 of Anubis's 98,947 points sit on a UV seam, so every triangle that
  touched one interpolated across the whole atlas. Harmless-looking at
  198,000 triangles — a speckle along the seams — and fatal once each
  triangle is forty times larger.
- **The decimator copied UVs from the nearest vertex.** Meshy's atlases are
  hundreds of tiny islands, and the nearest source vertex is on another one
  more often than not. 48.5% of the shipped Anubis's triangles spanned more
  than a quarter of the texture; 68.7% of the low-detail file's; Sekhmet and
  Zeus were 46% and 44% — their GLBs already carry seam-split vertices, and
  the nearest-vertex lookup picked between the copies at random.

The fix is in `tools/character.py`: the reader now splits vertices at seams
(one vertex per distinct point-and-UV, weights duplicated with them), the
decimator is MeshLab's quadric collapse **with texture** (via an OBJ round
trip, because the in-memory route refuses per-corner coordinates), with
seams preserved as boundaries and skin weights transferred afterwards from
the nearest source vertex, which is fine for weights because weights are
smooth. Normals are welded across seam copies so a seam is not a crease.
All three families were rebuilt and re-rendered: **zero smeared triangles**
in all 24 files, and the renders show the characters that were painted.
`pymeshlab` is a 106 MB wheel that also needs `libopengl0`; the tool says so
and falls back to a seam-frozen fast decimation when it is missing.

## Polygons: the actual comparison

| | triangles |
|---|---|
| Summoners War monster (2014, mobile) | ~2,000–5,000 |
| The raw Anubis export | 197,879 |
| **What ships now** | **4,999**, plus a 2,499 `_lod` for the ten-character stage |

Decimation, run for real over the whole family with `python3 tools/mesh.py anubis`:

```
anubis.usdz              197,879 → 4,999 tris    22.0 → 1.6 MB   1024 texture
anubis_lod.usdz          197,879 → 1,499 tris    22.0 → 0.5 MB    512 texture
anubis_<clip>.usdz  × 6  197,879 → 1,499 tris    21.9 → 0.1–0.2 MB each, 128 texture
                                                153.5 → 3.0 MB in the app bundle, 9 s
```

And over the two Meshy families, which arrive lighter (Meshy remeshes to the
requested 30,000 quads):

```
sekhmet.usdz              56,281 → 5,000 tris    6.8 → 1.7 MB   1024 texture
sekhmet_lod.usdz          56,281 → 1,589 tris    6.8 → 0.5 MB    512 texture
sekhmet_<clip>.usdz × 6   56,281 → 1,589 tris    6.9 → 0.2–0.3 MB each, 128 texture
                                                48.3 → 3.5 MB in the app bundle
zeus.usdz                 55,839 → 5,000 tris    7.2 → 1.8 MB   1024 texture
zeus_lod.usdz             55,839 → 1,980 tris    7.2 → 0.5 MB    512 texture
zeus_<clip>.usdz × 6      55,839 → 1,980 tris    7.3 → 0.2–0.3 MB each, 128 texture
                                                51.1 → 3.8 MB in the app bundle
```

Sekhmet verifies at 2.001 m, Zeus at 2.146 m against 2.15 (the decimator
shaves the crown), both with feet at y = 0, facing +Z, four influences, rest
equal to bind to 1e-15, and every animated frame life-size. After the seam
fix the families are 3.4, 3.8 and 4.0 MB with more vertices (a seam vertex is
two), and the `_lod` is 2,499 triangles; a battle uses the full model unless
there are eight or more combatants.

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

**Nothing is closed any more.** `assets.meshy.ai` and `cdn.meshy.ai` are on the
allow-list; `download` fetched all fourteen files (seven per family, 7 MB
each) in under a minute, and the untouched exports are committed in
`Art/Models/` beside the manifests, the same way the Anubis sources are.

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
- [x] **Seen on device**, twice: Anubis in a battle (right size, grounded,
  facing the enemies; marbled texture and an A-pose, both traced and fixed)
  and Sekhmet on the summon stage (upright, animated, over-exposed; the
  lights were retuned). The bundle holds 24 model files, eight per family.
- [ ] **Confirm the fixes on device** with More → Diagnostics: textures,
  the idle, the exposure, and the landscape framing.

### Phase 1 — the model pipeline *(done)*

Run in anger and measured above. The pipeline is `Art/Models` → `mesh.py` →
`Pantheon/Resources/Models`, one command per family.

### Phase 2 — a second and third character family *(Sekhmet and Zeus: done, unseen on device)*

Per family: a kit, a balance pass, five portraits, one mesh through Meshy, and
the pipeline above.

- **Sekhmet** — Ember bruiser, the roster's first damage archetype. Every
  variant's Eye of Ra breaks defence; the claws Burn, Slow, Glance, weaken or
  make unrecoverable depending on the element. Natural 5★, which also fills
  the gacha's 5★ tier for the first time.
  - [x] Kit, five variants, in `UnitDatabase.swift`; in the summon pool
  - [x] Balance model updated; the duel against Anubis sits at 81–88% for her
  - [x] Model, rig and six clips generated (task ids in the manifest)
  - [x] Downloaded, converted, decimated, verified: 3.5 MB in the bundle
  - [x] Five portraits, one generation and four reference edits; in the gacha
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
  - [x] Downloaded, converted, decimated, verified: 3.8 MB in the bundle
  - [x] Five portraits and the "Olympus Stirs" banner, which the game now
    offers; all fifteen characters are in the summon pool
- **Thoth** — Radiance support, a cleanse and an attack-bar push, so the
  Egyptians have a second support. Next.

### Phase 2b — the common tier and the training hall *(done)*

- **Shabti** — the 3★ tier: five elements of one tomb-servant figurine, a
  two-skill attacker a grade under Anubis. Portraits are recolours of the
  enemy's, with cut-outs; no mesh, so they stand in the world as sprites.
  Exists because a gacha with no common tier gave every common roll to the
  first 4★ in the list.
- **The Hall of Ka** (`TrainingView`) — power-up by feeding (a duplicate
  is a skill-up on top), evolution with same-grade fodder at max level,
  awakening with essences; the island's fourth landmark and a button on the
  collection.

### Phase 3 — the island *(built; painted; now landscape)*

Summoners War's town is not a 3D scene the player navigates. It is a painted
backdrop with a fixed camera and tappable hotspots. That is what `IslandView`
is: the app now opens on it.

- [x] `Landmark` model — title, anchor in the painting, unlock level,
  destination, upgrade tiers — and five landmarks in `IslandDatabase`
- [x] Tap targets mapped through the painting's aspect-fill frame, a glow on
  anything actionable (energy, scrolls, arena attacks), a count badge, a tier
  mark, locked state with a shake
- [x] A 1536 × 2048 backdrop — painted procedurally by `tools/island.py` so
  the screen had a horizon while the key was missing
- [x] The real painting. Two Gemini calls, not one: a 3:4 generation spread
  the island across a width a phone crops to 62%, so the arena would have
  been cut in half. It was generated at 9:16 instead and the sea extended to
  3:4 with a reference edit that left the island in place (measured: the
  centre differs by 7/255 with its best alignment at zero shift). The five
  anchors in `IslandDatabase` were then measured off the painting; the
  numbers are in `Docs/ART_2D.md` §6.
- [x] Landscape: a 2048 × 1152 painting for a phone held sideways, which
  shows its whole width and crops 9% top and bottom; anchors re-measured.
- [ ] Upgrade states of the buildings: a second and third painting per tier
- [ ] Phase A of the living island (units idling on it, particles, day and
  night); see *The road to Summoners War*

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

## The road to Summoners War

Asked directly — "can this reach Summoners War, or will it always look vibe
coded?" — the honest answer is a list, because the game is a list of systems
and each one is either there, half there, or missing.

| Summoners War has | Pantheon today | What it takes |
|---|---|---|
| Gacha with a common tier, rare tier, legendary tier, pity | ✅ three tiers; the 3★ tier is the Shabti family, 4★ Anubis, 5★ Sekhmet and Zeus; soft and hard pity | more families |
| Power-up by feeding, skill-ups from duplicates | ✅ the Hall of Ka | — |
| Evolution with same-grade fodder at max level | ✅ | — |
| Awakening with essences | ✅ | essence drops are in the campaign; a dungeon per element is the genre's source |
| Runes (relics): six slots, sets, sub-stats, upgrades | ✅ | a rune-removal cost, a reappraisal, the "Legend" grade |
| Turn-based combat: attack bar, elements, buffs, debuffs, leader skills | ✅ | more status kinds as families need them |
| Campaign chapters, arena, energy | ✅ one chapter, arena, energy | a Greek chapter; Giant's Keep-style dungeons that drop relics |
| Hundreds of monsters | 20 characters in four families | one family is ~1 hour, 53 Meshy credits and two Gemini calls; the pipeline is proven |
| Stylised, chunky, readable 3D characters | realistic-leaning text-to-3D; textures being fixed | concept art first, then Meshy image-to-3D from it; a rim-light and outline shader; see below |
| A living island: monsters wander, buildings animate, day and night | a painting with plaques | two phases below |
| Landscape only | portrait | one build setting, a re-solved battle camera, a compact HUD, a wide island painting |
| Server, accounts, live events, guilds, real-time arena | none, all local | a backend; out of scope for the build in this repository |
| Sound with voice lines, real music | synthesised effects and two synthesised loops | Suno/Udio for music, ElevenLabs for lines |

Two of those rows are what "looks vibe coded" actually points at, and both
have a concrete fix:

**Characters.** Text-to-3D from one sentence gives a plausible figure, not a
designed one — Sekhmet on the reveal stage was a tan figure in a red dress,
and her five variants differed by a wash. Two things changed in this session
and a third is under way:

- **The shading.** `MaterialTuner` now gives every imported material a
  half-Lambert two-band lighting ramp with a specular pop (form reads as
  painted, shadows lift instead of going black), a Fresnel rim in the
  element's colour, and a **real recolour**: every saturated pixel of the
  base texture that is not skin or fur takes the element's hue, computed
  once per model and element and cached, so the water variant wears water.
  None of it touches the art files.
- **Concept first.** `tools/genart.py --ref <portrait>` paints a designed
  full-body figure from the card — ornate armour, a big silhouette, a strict
  three-colour palette, an A-pose on a plain ground — and
  `tools/meshy.py generate <asset> --image <that png>` runs Meshy's
  image-to-3D on it instead of text-to-3D, then rigs and animates as before.
  The three concepts are in `Art/Concepts/`; the image-to-3D tasks for
  `sekhmet_v2`, `anubis_v2` and `zeus_v2` are in their manifests. When a
  result beats the text-to-3D model in `tools/preview.py`, it ships under
  the family's name.
- **Still to do:** an outline pass (a back-face expansion or an
  `SCNTechnique` edge pass), and per-element costume *variants* rather than
  recolours, which is how the genre makes five characters of one.

**The island.** Phase A, one session: the painting stays and comes alive —
the player's own units stand on it in their idle clips (real 3D over the
painting, positioned at the plaques), the pool glows and the obelisk beacon
pulses with particles, the sky tints through a day-night cycle keyed to the
clock, the camera drifts a little with a drag. Phase B, two or three
sessions and ~200 Meshy credits: a real 3D island — terrain, five buildings
as static meshes from Meshy's sculpture style, water, units wandering with a
walk clip, pinch-zoom and pan, tap-to-enter by hit-testing the building.
Phase A first, because it is most of the feeling for a tenth of the cost.

**On agents.** More agents help where work is independent and verifiable:
this session ran the model pipeline in one while the Swift changed in
another. They do not help with the one thing that made the earlier work
risky, which was writing Swift nobody compiled. That is fixed differently:
the repository now compiles and tests itself on GitHub's macOS runner on
every push, and the app photographs its own screens there, so a session
here sees the result within ten minutes. That loop, not headcount, is what
turns "vibe coded" into "engineered".

### How a session sees the app now

1. `git push` → `.github/workflows/build.yml` builds the simulator app and
   runs the 40 unit tests on `macos-15` (about six minutes).
2. The job then launches the app in the simulator once per screen, pinned
   with `-tour -tour-step N` (`TourView`, debug only): island, collection, a
   unit's detail, the Hall of Ka, summon, a 5★ reveal, a battle on auto,
   arena, More — several frames for the reveal and the battle. The frames
   go to an artifact at full size and, as small JPEGs, to the orphan branch
   `ci/screens`, force-pushed each run.
3. The session runs `python3 tools/ciframes.py`, which fetches that branch
   and lays the frames out on one sheet. A red build, a failing test or a
   broken screen is seen before the phone ever pulls the commit. The first
   tour taught two things the hard way: the simulator's first screenshot
   takes most of a minute, so the tour cannot be timed from inside the app,
   and a stage the account has not unlocked is a black screen. The second
   tour paid for itself at once: the summoning disc under a revealed figure
   was tumbling on its edge (a spin added to a tilted node's Euler angles),
   and a levelled team won the first gate before the first battle frame, so
   the tour's battle now waits for a command instead of fighting on auto.
   The third tour found the A-pose: four battle frames eight seconds apart
   with every unit in the same pose, while the same clip played on the
   summon stage. `UnitNode` started with its current clip already set to
   the combat idle, so the idle it asked for at birth was refused as a
   restart, and units stood in their bind pose until their first attack.
   Nothing on the pipeline side was wrong; the console block would never
   have shown it. The frames did, in one look.
4. On the phone, **More → Diagnostics** holds everything the app printed,
   with Copy and Share; and the **Playtest Log** artifact takes issue
   reports the session reads back from its database on request.

Cost: macOS minutes bill at ten times Linux, roughly 80–100 plan-minutes per
push. Settings → Actions on the repository turns it off.

## What to do next

1. **Pull, build, run in landscape** and walk `Docs/PLAYTEST.md`: the island's
   plaques, the retextured models in a battle, the idle, the Hall of Ka, a
   ten-pull, the Overview's green relic numbers. Log what is wrong in the
   Playtest Log and paste the block from More → Diagnostics.
2. **Read the log of the CI run** for the same commit — the contact sheet at
   the end of it is what the simulator saw — so a phone-only fault (GPU,
   sound, feel) can be told from a build fault.
3. **The living island, phase A**, then **Thoth** by the same four commands
   and two Gemini calls, then a Greek chapter so Zeus has somewhere to fight.
   Each is a session; none needs new tooling.

---

## What I can and cannot do

| | |
|---|---|
| 2D art at volume | ✅ 29 assets in ~40 min, proven — when a Gemini key is present |
| Sound effects | ✅ synthesised, in the repo |
| Read, normalise, decimate, re-export 3D | ✅ proven on the whole Anubis family |
| **Generate, rig and animate a 3D character** | ✅ **proven twice: Sekhmet and Zeus, 53 credits and ~12 minutes each** |
| Convert Meshy's rigged GLB to USDZ | ✅ proven on both families, after one real bug the verify step caught |
| Fetch the finished files | ✅ fourteen files in under a minute |
| Paint a family and an island | ✅ eleven portraits, a banner and the island in ~6 minutes of Gemini time |
| All code, logic, balance, integration | ✅ |
| Compile and test the app | ✅ on every push, on GitHub's macOS runner, ~6 minutes |
| See the app | ✅ the CI screenshot tour; `tools/preview.py` for a model file |
| Touch the app | ❌ — taps, feel, sound and the real phone are yours |

The 3D bottleneck is gone in practice, not just in principle: a character is
four commands and two Gemini calls, about an hour end to end including the
waiting, and it arrives verified and rendered. The compile gap is closed by
the runner. What this environment still cannot do is hold the phone.
