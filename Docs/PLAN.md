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

### Phase 2 — a second and third character family *(done; all three remade twice: concept-first, then in the stylised look)*

All three families were remade in this session from designed concepts —
see *The road to Summoners War* below for how and what it costs. The
bullets under each family describe the first, text-to-3D build; the
remakes replaced their files under the same names, so nothing in the code
or the checklist below changed.

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
- **Thoth** — done in Phase 2c below: the roster's first healer.

### Phase 2c — Olympus filled: the second roster *(done)*

Greece had one god and nothing under him, so a common roll on the Greek
banner had nowhere to land and the player saw "all Anubis". The user chose
the direction in a round of questions: characters and battle feel first, a
**stylised look with Summoners War proportions** for every character from
now on, Ares as the first new 5★, creatures at 3★ and heroes at 4★, Thoth
for Egypt, up to 550 Meshy credits. Everything below was built in one
session from those answers.

- **Seven new families, 35 characters**, in `UnitDatabase+Roster.swift`:
  Ares (5★ berserker: War Frenzy buffs himself and fills his bar, Slaughter
  hits harder the more the target has lost and can take another turn; awakened,
  every kill feeds him), Heracles (4★ defender whose Twelve Labours deal 30%
  of his own maximum health; the Nemean Roar provokes the line; awakened, a
  shield the first time he falls below half), Perseus (4★ attacker: two cuts,
  a Mirror Shield that is Defense Up for the team and a counter for him, the
  Gorgon's Gaze that takes the whole line's turn away the element's way;
  awakened, winged sandals at the start of battle), Thoth (5★ Egyptian
  healer: a 30% team heal with a cleanse, the Book of the Dead for Immunity,
  the element's blessing and 25% of bar; awakened, the weakest ally is healed
  at the start of each of his turns), and the 3★ tier of Greece — Hoplite
  (Phalanx: Defense Up for all and a shield on himself), Satyr (Wild Piping:
  a 15% team heal and Haste) and Harpy (Talon Rake twice, Screech Dive knocks
  the bar back). Every basic attack carries the element's signature debuff
  and every family has a leader skill; the three tables that make five
  variants of a character (`signature`, `control`, `blessing`) are shared, so
  the next family is a page of data.
- **Banners give their own pantheon.** The Duat Opens is the Egyptian pool
  with the Anubis family featured; Olympus Stirs is the Greek pool with the
  Zeus family featured; the Endless Scroll is everything. A pantheon banner
  that handed out the other pantheon's commons was the complaint.
- **Ten models in the stylised look**, 53 credits each, 530 in all (891 →
  361): the three remakes and the seven new. Ten Gemini concepts in one
  prompt style (five heads tall, big hands, chunky shapes, three-colour
  palettes, A-pose, weapon tight to the body, grey ground), then Meshy
  image-to-3D + rig + six clips, all ten pipelines at once — Meshy accepted
  the concurrency and rate-limited a few, which the tool waited out. Every
  file verified with zero smeared triangles. One lesson: the **satyr's goat
  hooves** are thin enough that the 1,499-triangle decimation of the clip
  files ate 12 cm of them and verify reported the feet 12 cm off the floor;
  `--clip-tris 3000` keeps them. Another: the ten pipelines' per-stage costs
  in the manifests are wrong because the balance was read while nine other
  tasks were charging; the total is right.
- **Fifty portrait cards from the concepts**: each family's ember card is a
  `--ref` edit of its own concept ("the same character, waist up, dark
  background, rim light"), and the four other elements are recolours of that
  card, so the card and the model are the same design. Gemini kept three
  families full-body on the first pass; a second pass with "cropped to the
  waist" fixed two and a third pass as a bust fixed Thoth.
- **Not committed:** the six clip GLBs per character (6–7 MB each, 400 MB in
  all) — `.gitignore` covers them, the manifests hold the task ids and
  `meshy.py download` fetches them again while Meshy keeps them. The base
  export of each character is committed. The superseded concept-first
  sources (`sekhmet_v2`, `zeus_v2`, `anubis_v3`) left the checkout; their
  manifests stayed.
- **Awakened forms** (asked for straight after: "there needs to be a base
  and then awakened"). Every awakenable character has two cards now: the
  base and `portrait_<id>_awakened.png`, an edit of the base card into a
  ceremonial version of the costume with glowing markings, glowing eyes and
  a halo — fifty more Gemini edits. An awakened unit shows its awakened card
  everywhere a card appears (`ModelSpec.portraitName(awakened:)`, which falls
  back to the base card until the file ships), its awakened name (already
  the case), and on the stage the **awakened look**: the costume accent
  glows in the element colour (`costumeGlow` in the surface shader), the
  rim widens and brightens, and an aura of light rises from the feet
  (`VFXLibrary.aura`). The Hall of Ka's Awaken panel shows the two forms
  side by side before the player pays, and a successful awakening plays the
  summon reveal with the awakened form under **AWAKENED**. The loader looks
  for `<asset>_awakened.usdz` first and uses it with its own clips when a
  family ships a second mesh; none has yet — that is 53 credits a family,
  and the ten base meshes took the session's budget — so today the awakened
  form is the base mesh with the glow and the aura, and the card carries the
  costume change.
- **Not done:** awakened meshes (above), a model for the Shabti (they remain
  sprites; 53 credits when wanted), the Roman Legionary (Rome is a pantheon in the data with no banner
  yet; the user chose a Greek Hoplite now and Rome later), and a Greek
  campaign chapter.

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

### Phase 3b — the 3D stages *(built; being photographed)*

Asked for "a cool 3D background for the battles and the summon, like
Summoners War", and given three answers — up to 150 credits of props,
floating ruin platforms, a stone summoning circle — the stages stopped being
pictures. `StageBuilder` (Render) assembles a set from parts, no scene file:

- **The platform**: a cylinder with a painted floor on top (`floor_sandstone`
  or `floor_marble`, tileable, Gemini), a cliff face round the side
  (`rock_cliff`), a ring of boulders at the rim and rock chunks hanging below
  and beyond it, bobbing — the sign that the whole thing is in the air.
- **Props**: ten Meshy text-to-3D models shipped by `tools/prop.py` as
  `prop_<name>.usdz` — an Egyptian set (seated Anubis colossus, obelisk, lotus
  column, brazier, sphinx) and a Greek set (Doric column, broken column, Zeus
  statue, tripod brazier, temple ruin) — placed by a recipe per environment,
  each with a built stand-in (a column, an obelisk, a block in the stage's own
  stone) for a prop that has not shipped, so a set never has a hole in it.
- **Fire and air**: braziers with a flame and a flickering omni light, drifting
  additive mist planes, slow dust motes.
- **The distance**: the environment's painting on a 150 m plane 70 m behind
  the platform, so the camera's lean puts parallax between the set and the
  world beyond, and the painting's land reads as a world far below.
- **The summoning circle**: a rune dais (`rune_ring`, additive, in the element
  colour, turning) on a small floating rock, a half-ring of pillars and two
  braziers behind the figure in the summoned unit's pantheon, the colossus or
  the temple ruin further back, mist and dust; the SwiftUI glow and rays still
  show between the pillars.

**What the photographs taught, in three passes.** The first set's platform
was too wide for its edge to come into frame, so it read as a floor rather
than a thing in the air; four braziers and the key lit the sandstone near
white; and the brazier fire drew as black squares, because the particle
sprite was an opaque picture on black that only additive blending can hide
(it is a white sprite with real alpha now, which draws right under any
blend). The second pass showed the summon stage's view drawing its own
rectangle where the floor stopped, a pillar under the words, and an arena
close-up taken from inside a front brazier. The set is now radius 7.6 with
the edge a third of the way down the frame, the floor darker per stage, the
fire dimmer, the painted horizon lower, the reveal's view edge to edge with
its pillars behind and to the figure's left, the battle braziers all behind
the enemy line, and no rim boulders on the front arc where the impact shot's
camera lands.

**The cost was wrong.** Text-to-3D was estimated at 15 credits a prop (5
preview + 10 refine) and cost 30: ten props took 300 credits, twice the 150
agreed, and the balance is 61. The estimate should have been checked on one
prop before nine more were launched. Nothing else can be bought until the
account is topped up; the next character or the awakened meshes wait on that.

### Phase 2d — the third roster, two new realms and the Halls *(built; the art is landing)*

Seventy-nine families are in the code (see *The detail pass and batch 3*
below for the last thirty-six): the eleven hand-written ones and
thirty-two from one table (`UnitDatabase+Families.swift`). A row is the
numbers, the names and the words that make a family itself; what varies
by element is the shared tables; what varies by role is one of eight
**kits** (striker, duelist, marksman, bruiser, warden, healer, oracle,
trickster), so a player who has learned one striker knows every striker's
shape. The Norse pantheon is live with the **Ravens Gather** banner.

- Egypt +9: Horus, Isis (5★); Set, Bastet, Sobek, Hathor (4★); Scarab
  Knight, Mummy, Jackal Warrior (3★)
- Greece +10: Athena, Poseidon, Hades (5★); Apollo, Artemis, Hermes (4★);
  Minotaur, Cyclops, Amazon, Medusa (3★)
- Norse +13: Odin, Thor, Freya, Loki (5★); Tyr, Heimdall, Hel, Skadi (4★);
  Valkyrie, Draugr, Berserker, Frost Troll, Dwarf Smith (3★)

The art, in the order it lands: stylised concepts for all thirty-two
(`Art/Concepts/*_sw.png`); Meshy models for every family (twenty-nine
rigged in one session, four more from A-pose redraws after "pose estimation
failed" on Bastet, Hathor, Hades and the text-to-3D Jötunn — the fix each
time was a concept with a gap between the arms and the body and both feet
showing); the five element cards per family and the awakened cards for the
twenty 4★/5★ families (`tools/batch/portraits_batch2.sh`, ~240 Gemini
calls, which is a day's quota, so it runs across two sessions and skips
what exists). The gacha gates on cards, so a family joins the pool the
morning its five cards are in the bundle.

**Two new realms.** Six generated chapters — Olympus 1–3 (the Gate, the
Aegean Cliffs, the Marsh of Lerna) and Yggdrasil 1–3 (the Midgard Fjord,
the Roots, the Hall of Jötunheim) — on six new `BattleEnvironment`s with
their own painted backdrops and `StageBuilder` recipes (the Greek set
stands the Zeus statues and Doric columns on the Egyptian marks; the Norse
set is rune stones, a longship prow, the world tree's roots and hall
pillars on slate and ice). The creatures of each realm fight with the
roster's own models and cards and a two-skill enemy kit (`enemy_minotaur`
wears `minotaur.usdz`); the bosses — the Hydra and the Jötunn — are
unrigged meshes the loader moves procedurally. **The curve is measured**:
later chapters field the same creatures at a higher grade times a
chapter-wide difficulty, not at absurd levels, and `tools/balance.py
--chapters` prints the win rate of four ladder teams on the first, middle
and boss stage of every chapter. Olympus 1 opens to a levelled 4★ team,
Olympus 3's Hydra needs 5★s with relics, the Jötunn needs a maxed 6★ team.

**The Halls of Essence** (`DungeonDatabase`): one hall per element, five
floors, a boss on every floor, open every day and cleared as often as the
energy holds. This is where the element essences come from and where the
relics worth keeping start (the floor sets the grade, 3★ on B1 to 6★ on
B5). A floor is a `Stage` whose chapter is the hall, so the campaign's
plumbing runs it — progress, the briefing, the battle, auto-repeat — with
no special case. `--halls` prints the curve: B1 for a 4★ team, B3 for 5★s
with relics, B5 for a maxed 6★ team.

**The grind conveniences.** The briefing asks for 1, 5, 10 or 20 runs;
on a repeat the battle swaps in a fresh engine per run on auto, shows
"Run 3 of 10" between them, and tots the loot up for one panel at the end,
stopping on a defeat or an empty energy bar. The wallet bar counts down
to the next point of energy. Speeds ×1/×2/×3 were already there.

**Relic management** (`RelicInventoryView`, `RelicService`): an inventory
with set tallies (7/2 Fury…), slot and set filters, a role picker and an
**efficiency** dial — the relic's score against the best its grade, slot
and level could have rolled for that role — bulk selling with locks
honoured, and a detail sheet that upgrades, **reappraises** (from +9,
every sub stat rerolled, main stat and level kept, two upgrade-costs'
worth of drachma) and locks. The unit sheet gained a picker per slot and
its active sets. `Relic.isLocked` finally does something.

**The bazaar** (`ShopService`, `ShopView`): scrolls, energy, relic packs,
essences and a laurel exchange, all for the game's own currencies, and a
free daily offering (a scroll, 2,000 drachma, 10 energy). No real money
anywhere. It opens from the wallet on the island and from More. The
`Player` gained `lastDailyPackClaim` as an optional, which is the rule for
every new save field: the synthesised decoder tolerates a missing optional
and nothing else.

**The living island, phase A** (`IslandSceneView`): the campaign team
stands on the painting in its idle clips — an orthographic SceneKit layer
between the painting and the plaques, one world unit per screen point, so
a stand point is a point on the painting and a figure is a tenth of the
screen tall — with a contact shadow under each, sparks over the pool, a
flame at the obelisk's tip, and the hour's colour multiplied over the
painting (nothing by day, warm at dusk, blue at night).

What the session cost: 3,061 Meshy credits at the start, the floor the
user set at 500. Wave 1 (Egypt) 9 × 53, waves 2–3 (Greece, Norse) 23 × 53
including the Shabti, the props and beasts 30–300 each (text-to-3D previews
are charged by what Meshy generates, not a flat rate), then four A-pose
redos and two awakened meshes (Sekhmet, Zeus). Gemini's 250-a-day cap was
hit with about 150 cards to go and one concept (Loki: the first draw was a
photo of an actor, deleted; the second was refused; the third is
tomorrow's).

### Phase 2e — the first playtest of the big build, and what it asked for *(built)*

The phone said four things about the previous commit, and three of them
were one bug: the Chapters/Halls switch did nothing, the banner chips did
nothing, and the stages after the first would not open. Every painting on
those screens is scaled to fill a short strip and clipped — and SwiftUI's
`.clipped()` clips drawing, not touch, so a 2048-square backdrop in a
118-point band was swallowing taps 340 points above and below itself. One
modifier per painting. The fourth was the third skill blanking the screen:
the cinematic-orbit shot's hand-rolled look-at was half a turn off and
showed the empty side of the stage.

What the phone asked for, all built:

- **A way to earn.** `QuestService`: daily missions (clear three stages,
  a hall floor, an arena win, a summon, a power-up, a relic upgrade, the
  daily offering, thirty energy; a Pantheon scroll for the set), feats
  (first 5★, summon counts, arena wins, hall floors, a +15 relic, an
  awakening, a 6★, unit counts, summoner levels, every chapter), a
  seven-day login gift, and 25 divinity a summoner level. Scrolls drop
  from every stage now (unknown, mystical; pantheon on bosses) and from
  the halls (the element's own). The Missions screen sits beside the
  wallet with a badge.
- **Scroll packs like Summoners War.** Unknown (3★ commons), Divine
  (4★+), Light & Dark, Fire, Water and Wind scrolls: each is a banner
  whose pool is the slice of the roster its name promises and whose
  scroll is its own currency, sold in the bazaar (Unknown for drachma,
  the rest for divinity, two for laurels). The summon screen has two chip
  rows with counts. Six banner paintings and a world map are in the
  day-two Gemini script.
- **A map.** `WorldMapView` (realms, chapters, why a chapter is shut) and
  `ChapterMapView` (the painting, a dotted road, medallions: gold tick,
  pulsing ring, lock, boss crown). The list rows remain under the map.
- **Five tabs.** Settings opens from the Obelisk.
- **The camera stays put.** After the first fights on the phone the camera
  was found at a "weird spot" on the player's turn: the old close shot's
  look-at constraint survived the turn change because cancelling the shot
  skipped the completion that cleared it. Fixed, and then the genre's rule
  adopted: one framing for the whole fight, a short push toward an
  ultimate's caster, a shake on heavy hits, nothing else. The cinematic
  cuts live behind More → Sound & camera.
- **Density.** "Lots of blank space, make things smaller like Summoners
  War": the painted chrome is drawn at 1/1.4, every font at 0.9, cards
  92 → 76 (72 in the picker, 60 in the lineup), grids one column denser,
  outer paddings 16 → 12, panel paddings 14 → 10, the primary button
  slimmer and no wider than a hand, banners 118 → 88, the chapter map
  first on its screen.
- **The HUD.** An attack gauge at the top centre (portraits sliding on
  one track), wider health bars over the figures, the selected skill's
  name and description above the skill row, and a card on hold.

### Phase 2f — the Labyrinth, waves, and the sheet in the genre's shape *(built)*

The second playtest note was about shape, not bugs: "why click into a
menu first — the building should be the map", "a dungeon building like
the genre's, a couple of stages and a boss, relics at the end, levels",
and "the character view and the relic selector are not it". Three
answers:

- **The gate is the map.** `CampaignView` no longer has a Chapters/Halls
  switch and a realm list in front of the map; it opens on the chapter
  the player is in (a strip of chapter chips, the chapter's road below),
  and the realms overview is a sheet. One tap from the island to a stage.
- **The Labyrinth.** A sixth landmark on the island (the palm grove right
  of the circle, anchor 0.62/0.42). Inside: three relic dungeons
  (`DungeonDatabase.labyrinths`) — the Vault of the Colossus (the sentinel;
  Fury, Aegis, Bulwark, Zephyr, Fates, Vigil), the Lair of the Hydra
  (Thunder, Ruin, Wrath, Ichor, Titanfall, Chains) and the Necropolis of
  the Devourer (Ammit; Oracle, Wards, Styx, Nemesis, Chains, Bulwark) —
  ten levels each, and the Halls of Essence under the same roof. A level
  is **one battle of three waves**: two of the roster's mobs, then the boss
  at ×1.6 with two more. That needed waves in the engine: `Stage.laterWaves`,
  `BattleEngine.spawnWaveIfNeeded()` at the top of the turn loop
  (`checkForEnding` no longer calls a clear field a win while waves
  remain), a `.waveStarted` event carrying the arrivals so the scene can
  remove the fallen and walk the new wave in from the back, the HUD's
  "Wave 2/3" chip, and the briefing listing W1, W2, BOSS. The drop is
  guaranteed and restricted to the dungeon's sets (`StageRewards.relicSets`),
  3★ on B1–3, 4★ on B4–6, 5★ on B7–9, 6★ on B10. `tools/balance.py
  --labyrinths` runs a team through all three waves with its wounds and
  cooldowns kept: B1 falls to four 3★s at level 20, B4 to 4★s at 35, B7 to
  5★s with relics (the Colossus even to 4★s, 72%), B10 to maxed 6★s — the
  Hydra and the Necropolis hold against 5★s at B10, the Colossus does not
  (98%), which is the soft entry the genre also has.
- **The sheet.** `UnitDetailView` is one landscape screen: card, level
  bar, power and Power up / Evolve / Awaken on the left; the six relic
  slots in a ring around the element in the middle, slot 1 at the top and
  clockwise from there, each tile showing set glyph, main stat, grade and
  +level; the eight stats with their relic bonus on the right, with the
  leader skill and the awakening line under them; the skills along the
  bottom, the selected one's words, cooldown, estimated damage and
  skill-up dots beside the tiles. The lore is behind a book in the
  toolbar, auto-equip beside it, awakening in its own sheet with both
  forms. `RelicPickerView` is the genre's rune screen: candidates best-fit
  first on the left, and on the right the relic in the slot, the pick,
  every stat before → after with the delta and the sets completed or
  broken — computed by resolving the unit with the pick in the slot
  (`ProgressionService.resolve(_:blueprint:equipped:)`) — and then Equip,
  Take and equip, or Unequip.

The tour grew to eighteen screens (the Labyrinth, a dungeon's levels, the
picker), the halls step goes through the Labyrinth, and the chapter-map
step photographs the campaign tab as it now opens.

**The second pass — "can you do the relic dungeons?"** The first pass
borrowed everything: the bosses were a chapter mob and two hall bosses,
the stages were chapter stages. Now each dungeon is its own place:

- **Bosses.** The Colossus (`boss_colossus`: a statue that stood up, 5★
  radiance, 4.5 m, a stunning fall) and the Unwrapped King
  (`boss_unwrapped_king`: 5★ umbra, quick, a ledger that slows the line);
  the Hydra keeps the Lair. Their meshes are Meshy image-to-3D from A-pose
  concepts (`tools/batch/labyrinth_art.sh`), 53 credits each, queued for
  the night's run behind Loki, Hades and Bastet; until they land the
  loader's stand-in fights in their place and the cards are placeholders.
- **Stages.** Three `BattleEnvironment`s (`colossusVault`, `hydraLair`,
  `necropolis`) with their own `StageBuilder` recipes — the vault's
  colossi close in under gold-lit dust, the lair drowned in green mist,
  the necropolis violet-lit among sphinxes — and their own paintings,
  painted the same night; `backdropName` shows the parent painting until
  then, so nothing is ever grey.
- **Mobs.** The vault is guarded by the sentinels, the necropolis by
  shabti with Ammit prowling the second wave, the lair by the marsh.
- **The run is photographed.** A `dungeon_battle` tour step fights
  Vault B1 on auto for four frames, so the second and third waves are seen
  walking on and the Wave chip counting.

**Meshy for the stages.** The user asked for the maps and stages to use
Meshy props and not look sloppy. The credit rule is the constraint: 809
credits, a floor of 500, and the night's five characters (three roster
families, two bosses) spend 265 — 44 to spare, and a text-to-3D prop costs
30–300. The prop set that would make the three dungeons their own places
is six pieces: a sealed vault door and a fallen pharaoh head for the
Colossus; a sarcophagus and a cluster of canopic jars for the Necropolis;
a dead marsh tree and a bone pile for the Hydra. Estimate 200–400 credits.
It waits for a top-up; the recipes have the marks ready.

**"This is not how a boss battle should look."** The phone's third note
came with the Vault's boss wave: a grey capsule under a wall of yellow.
Three causes, all fixed in one pass. The boss had no mesh yet, and the
loader's stand-in is a primitive — `ModelSpec.standInAsset` now names a
shipped mesh to fight in a missing one's place at the spec's height, with
the stand-in's clips, so the Colossus is a 4.5 m sentinel and the
Unwrapped King a 3.2 m mummy until their own meshes land. The bloom
(0.55 over a 0.85 threshold) turned a sunlit sandstone floor into a sheet
of light — it is 0.3 over 0.94 now, and the vault's palette cooled. And
the camera was too low and too close for a boss: the landscape solve
moved from 5.5 m up / 24° down to 7.2 m up, 11 m back, 30° down at 34°,
the genre's high three-quarter view, with both lines and the platform's
far edge in frame and a figure a quarter of the screen tall.

The same pass answered "the model is not right and the attack is not
fluid": the shipped Sekhmet is the lioness from her concept (the sheet
proves it) but from behind at the low camera her mane read as hair; the
higher camera shows the head. The melee dash is a 0.3 s leap instead of a
0.16 s slide, clips cross-fade over 0.22/0.30 s, one-shots are capped at
2× speed with longer contracts, every hit lands in its element and a
closing strike draws a slash. And "I have no idea what is happening to my
characters": status tiles over the bars with glyphs and turn counts, named
chips in the actor plate, a boss bar, an ultimate cut-in, a slimmer HUD
that leaves the field clear, and lighter damage numbers.

**Relic power-up, the rune way.** The user's second note: "the same
upgrade system as the rune system for our relics". The rules the genre
publishes (sure to +3, then a chance of failure that costs the mana and
keeps the level; a sub stat at +3/+6/+9/+12, new while under four, then
grown; a main-stat jump at +15) are all in: `RelicService.powerUpChances`
runs 100/100/100/95/90 … 40, `upgrade` returns a `PowerUpOutcome`, the
sub-stat rule stops at +12, `effectiveMainStat` is linear to +14 and jumps
to 3× at +15. `RelicDetailView` is the screen: odds, cost, the next value,
the level track, the last roll marked, a glow or a shake. The data sites
with the exact per-level table are refused by the network policy, so the
numbers are modelled, not copied; the expected drachma to +15 for a 6★
comes out about 1.7× the no-fail bill (`balance.py`, the economy report).

### Phase 2g — the second playtest's four asks *(built 2026-09-10, evening)*

The owner played the big build on his phone and asked for four things, each
with a screenshot. All four are built; each is one screen or one file.

- **The Hall of Ka as a place.** "Can we do something for the consuming
  like with the summoning temple?" `TrainingView` is the summon screen's
  shape: a painted sanctuary (`hall_of_ka_bg`, 16:9, its empty dais in the
  left third), the chosen unit's real model standing on the painted dais in
  a transparent SceneKit view the size of the frame (`AltarStageView`), a
  rail of cards down the left, the mode's panel over the right, and a rite
  on the altar for every commit: orbs of the fed units' element fly into the
  figure and it flares under a beam, an evolution or awakening swells it in
  a pillar of light, "LEVEL UP!" springs in over it.
- **The reward chest as a model.** "That chest SUCKS." A Gemini concept →
  Meshy image-to-3D (30 credits) → `prop.py --split-lid` cuts the one mesh
  into the box and a lid hinged at its back edge → `RewardChestView`: hop,
  shake, the lid swings back past open, a pillar of gold light, the flash,
  the chest lifts away and the spoils stay. A lesson on price: the `cost`
  a Meshy manifest records per task is a balance delta polluted by parallel
  tasks; the plan's measured 30 a prop stands, by either route.
- **Every element fights its own way.** "We cant have all 5 of the
  elements of each character have the same attacks." The sixty-eight table
  families' second and third skills are the element's (`elementalSkill`:
  forty (kit, element) pairs in one grammar — fire burns and grows, water
  freezes and drags the bar, wind repeats and hastens, light shields and
  reveals, dark drains and brands), named per family by
  `elementalSkillNames`; the eleven hand-written families get the same by
  hand. `balance.py --variants` measures the five forms of one family per
  kit; the sim now reads "(Crit)".
- **Effects.** "It cant be your bullshit red circle." No AI emits a finished
  effect, so: Gemini paints twelve element sprites on black
  (`tools/batch/vfx_sprites.sh`), `tools/vfx_ship.py` gives them alpha,
  `VFXLibrary.puff` throws them, each impact is built from its element's
  two, `projectile` flies the element's sprite from a ranged caster to the
  victim on an arc, and one Veo 3.1 clip (the owner's word: one now, about
  ten dollars a month after) cut by `tools/veo.py` into a 32-frame flipbook
  is the fireball's burst. An effect authored in Xcode's particle editor
  and dropped in as `<identifier>.scnp` replaces the code-built one.

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
| Hundreds of monsters | 55 characters in eleven families (ten with models) | one family is ~1 hour, 53 Meshy credits and six Gemini calls; ten were made in one session |
| Stylised, chunky, readable 3D characters | ✅ every model is image-to-3D from a stylised concept in Summoners War proportions, with a painted lighting ramp, a rim light and a per-element recolour | an outline pass |
| Melee units that close and strike, hits that land | ✅ a dash to the victim for single-target attack clips, a white flash on the hit, the camera leans into every action | impact frames read off each clip |
| 3D battle stages the camera moves around | ✅ floating ruin platforms with props, fire, mist and a painted distance; a stone summoning circle | more props per pantheon; a Greek set on a Greek chapter |
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
  base texture that is not skin or fur takes the element's hue, so the water
  variant wears water. The recolour runs in a surface shader modifier, per
  fragment on the GPU: the first version did it on the CPU once per texture
  and element, which stalled the main thread for the whole loop (the fourth
  tour's reveal never got past its dark charge) and would have kept five
  copies of every texture in memory. None of it touches the art files.
- **Concept first.** `tools/genart.py --ref <portrait>` paints a designed
  full-body figure from the card — ornate armour, a big silhouette, a strict
  three-colour palette, an A-pose on a plain ground — and
  `tools/meshy.py generate <asset> --image <that png>` runs Meshy's
  image-to-3D on it instead of text-to-3D, then rigs and animates as before,
  and `tools/mesh.py <asset>_v2 --as <asset>` ships the result under the
  family's name so the game's `ModelSpec` never changes. Done for all three
  in one session, and the difference is not subtle: Sekhmet is a black
  lioness in a gold sun-disc crown with a cobra, a lapis and carnelian
  collar, a crimson war skirt with hanging gold plates and a khopesh that
  follows her hand through every clip; Zeus wears gold scale armour and a
  gold-edged himation and holds a thunderbolt; Anubis has a striped nemes, a
  gold and obsidian chest plate and a lapis-panelled kilt. Zero smeared
  triangles in any file. Costs: 30 credits for the image-to-3D (texturing
  included), 5 for the rig, 18 for six clips — 53 a character, the same as
  text-to-3D. One lesson: Meshy's rigger refused the first Anubis concept
  ("pose estimation failed") because of the tall staff standing beside him;
  the empty-handed redo rigged at once. Props go in the hand or nowhere.
  The concepts are in `Art/Concepts/`; the superseded text-to-3D exports
  are in git history (before this commit) and no longer in the checkout.
- **The look, decided.** Asked which look every character should have, the
  user chose stylised Summoners War proportions over the painterly
  semi-realistic look the first remakes had. Every model in the bundle is now
  from a concept in that style (`Art/Concepts/*_sw.png`), and every card is
  from its concept, so the character on the card is the character on the
  stage. The per-element recolour changed with it: it moves only the design's
  primary accent (`ModelSpec.costumeHue`, gold on every character so far),
  because recolouring everything saturated made an ember Sekhmet one shade of
  red on the fourth tour's reveal; her lapis and crimson now stay.
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
   have shown it. The frames did, in one look. The fourth tour showed the
   idle playing and Zeus's feet in frame, and a reveal that stayed dark for
   twelve seconds — the CPU recolour of the base texture, running inside the
   stage view's construction on the main thread, in a debug build. It moved
   to the GPU. That tour also showed the limit of frames alone, so the job
   now publishes each step's console beside them (`<step>-console.txt`: the
   app's stdout and stderr with the frameworks' os_log lines mirrored in,
   plus `system-log.txt` for the process) and `tools/ciframes.py` prints the
   lines that matter — the `[ModelLibrary]` block, anything that says error
   or shader. The tour photographs an arena battle as well as the campaign
   one, and both battles issue a basic attack every four seconds, so the
   frames catch dashes, hits and flashes instead of a line waiting for a
   command. The first fighting tour showed exactly that — a Thunderbolt, a
   dash, a fallen enemy, the awakened glow — and one thing to tune: the
   impact and push-in shots, set for the earlier slimmer models, cut the
   chunky ones off at the crest, so they now sit a stride further back.
4. On the phone, **More → Diagnostics** holds everything the app printed,
   with Copy and Share; and the **Playtest Log** artifact takes issue
   reports the session reads back from its database on request.

Cost: macOS minutes bill at ten times Linux, roughly 80–100 plan-minutes per
push. Settings → Actions on the repository turns it off.

## What to do next

1. **Pull, build, run in landscape** and walk `Docs/PLAYTEST.md`. The phone
   the last screenshots came from was still on the build before every fix in
   this document; nothing below has been seen on a device.
2. **Read the log of the CI run** for the same commit — the contact sheet at
   the end of it is what the simulator saw, and `<step>-console.txt` beside
   it is what the app said — so a phone-only fault (GPU, sound, feel) can be
   told from a build fault.
3. **Finish the third roster's art** (the next day's Gemini quota): run
   `tools/batch/portraits_batch2.sh` again for the cards it could not
   paint, redraw Loki and Hades in the A-pose, run them through Meshy as
   `loki` and `hades_v2`, ship with `mesh.py hades_v2 --as hades`. Then
   the remaining awakened meshes (Thoth, Ares) if the credits allow
   — 53 each, never below the 500 floor.
4. **Play the new realms and the halls on the phone.** The curve was
   measured in the simulator against Anubis teams; the sim cannot see a
   heal, a shield, a strip or a provoke, so the healers and tricksters
   are rated as floors, and a real team may find Olympus 2 easier or the
   Jötunn harder than the table says. Move a chapter's `difficulty` and
   `enemyStars` in `StageDatabase.swift` and `tools/balance.py` together.
5. **Tune Ares.** The balance sim cannot see a self-buff or an extra turn,
   so it has him losing to Sekhmet; on the phone he may not. Decide from
   play, then move the numbers in `UnitDatabase+Roster.swift` and
   `tools/balance.py` together.
6. **Rome** (a Legionary and a banner) by the same recipe as Greece; the
   living island's phase B (painted upgrade states for the buildings).

---

## What I can and cannot do

| | |
|---|---|
| 2D art at volume | ✅ 29 assets in ~40 min, proven — when a Gemini key is present; **250 images a day** is the key's cap, and a roster's cards are about 240 |
| Sound effects | ✅ synthesised, in the repo |
| Read, normalise, decimate, re-export 3D | ✅ proven on the whole Anubis family |
| **Generate, rig and animate a 3D character** | ✅ **proven forty-six times; twenty-three at once in one session, 53 credits and ~15 minutes each; `meshy.py` waits out the plan's queue cap** |
| Convert Meshy's rigged GLB to USDZ | ✅ proven on both families, after one real bug the verify step caught |
| Fetch the finished files | ✅ fourteen files in under a minute |
| Paint a family and an island | ✅ fifty cards from ten concepts in ~25 minutes of Gemini time, three families at a time |
| All code, logic, balance, integration | ✅ |
| Compile and test the app | ✅ on every push, on GitHub's macOS runner, ~6 minutes |
| See the app | ✅ the CI screenshot tour; `tools/preview.py` for a model file |
| Touch the app | ❌ — taps, feel, sound and the real phone are yours |

The 3D bottleneck is gone in practice, not just in principle: a character is
four commands and two Gemini calls, about an hour end to end including the
waiting, and it arrives verified and rendered. The compile gap is closed by
the runner. What this environment still cannot do is hold the phone.

## The detail pass and batch 3 (2026-09-09)

The playtest's verdict on the characters: too cartoony, and an attack that
"pulls the leg out". Measured causes, in order of weight:

1. **The texture prompt.** Every mesh since the first wave was textured with
   "cel-shaded with crisp baked highlights", which Meshy renders as three
   flat tones per part. `tools/batch/wave_launch.sh` now asks for painted
   detail: engraved and embossed metal with worn edges, cloth with a weave
   and stitched trim, hair and fur in strands, leather with grain, soft
   natural shading. The concept style for new families
   (`concepts_batch3.sh`) says the same, since the model takes its texture
   from the drawing.
2. **The budget.** 5,000 triangles and a 1024 texture were chosen for a
   portrait phone at 3v3. The landscape camera puts a figure a quarter of
   the screen tall in battle and most of it in the summon reveal and the
   unit sheet, where 1024 texels over a 2 m body is a texel a pixel.
   `tools/mesh.py` ships 9,000 triangles at 2048 (LOD 3,500 at 1024; the
   clip carriers stay 1,500 at 128, the game reads only their tracks). A
   base file grows from about 1.9 MB to about 5 MB.
3. **The ramp.** `ModelLibrary`'s two-band ramp (`smoothstep(0.28, 0.72)`)
   turned a face into one tone and a cheek. It is `smoothstep(0.16, 0.86)`
   over 0.30 + 0.70 now, with a 36-power specular at 0.42 so metal reads,
   and the rim is 3.2 / 0.42 instead of 2.6 / 0.55, which had outlined every
   figure in white.
4. **The clips.** 96 "Kung Fu Punch" throws a leg; 237 "Charged Axe Chop"
   plants a wide stance and swings overhead, which reads as a stumble on a
   robed god. `tools/meshy.py` defaults to 219 Right-hand Sword Slash,
   242 Charged Slash and 102 Sword Judgment, and `CLIP_SETS` gives the kits
   that do not swing a blade their own: `heavy` (128 Heavy Hammer Swing,
   127 Charged Ground Slam), `caster` (129 Mage Spell Cast, 125 / 126
   Charged Spell Cast), `archer` (224 / 226 Archery Shot, 222 Draw and Shoot
   from Back). A wave spec's fifth field names the set; a spear-bearer adds
   `,attack_basic=240` (Thrust Slash).

**Costs.** The manifests' per-stage `cost` is a balance delta read between
polls, so it is noise whenever runs overlap (Odin's image stage shows 90,
Harpy's rig 135). Sequential runs and the account itself agree: 30 for the
image-to-3D, 5 for the rig, 3 a clip — **53 a character**, confirmed again
today (7,809 → 7,650 for three). The plan is 8,000 credits with a floor of
**2,000** since 2026-09-11 (3,000 before that); `wave_run.sh` reads the balance before every launch and counts
what the launches of the same run still owe.

**What the floor buys.** Remakes of every family cut with the old prompt
(`remake_wave.txt`: 3 flagships done by hand, 21 more 4★ and 5★, 16 3★ as
the last block at a 3,300 floor) and thirty-six new families
(`wave3.txt`, with batch 2's five leftovers at the top): 60 characters,
3,180 credits, leaving about 4,470 before the 3★ block and about 3,620
after it. The gate is Gemini, not Meshy: 250 images a day, and batch 3
needs 36 concepts plus 300 cards on top of the 150 the third roster still
owed, so it spans three nights of routines (Sep 9, 10, 11 at 23:50 UTC).
A family joins the gacha when its five cards land; its mesh can arrive
later (the loader's stand-in covers the gap).

**The repository.** The raw exports in `Art/Models` are tracked (539 MB,
392 of it base meshes) and will double; the CI checkout is now sparse and
skips `Art/` entirely, since the build needs only `Pantheon/Resources`. From
this pass on only the base export and the manifest of a character are
committed: the six per-clip GLBs (6–7 MB each, a copy of the mesh with one
track) are ignored and refetched with `meshy.py download` when needed.

**The bundle.** The bigger textures and three hundred new cards would have
put the app past a gigabyte, so the paintings became JPEGs
(`tools/shrink_art.py`, quality 92): the two resource folders went from
248 MB to 51 MB, which is more than the meshes gained. Only files with an
alpha channel and the tiling stage textures stay PNG. `UIImage(named:)` is
indifferent to the extension; the two existence checks by name and extension
now go through `BundleArt`.

**What it will weigh.** A family at the new budget is about 7.5 MB (4.5 base,
1.7 LOD, six clip carriers at 0.2), so seventy-nine families are about
590 MB of meshes, and their cards about 155 MB as JPEG (they would have been
858 as PNG). An app of roughly 800 MB installs from Xcode without complaint;
if it ever needs to come down, the texture is the cheap knob (1536 px instead
of 2048 takes a base file from 4.5 MB to about 2.8) and the LOD is the next
one, not the triangle count, which is what fixed the silhouette.

**What it costs CI.** The roster went from about 215 blueprints to 395, and
the unit-test step went from 4.5 minutes to 10.4 (the tour is unchanged at
about 13.5), so a run is now roughly half an hour: read it, do not push over
it. The sixty-eight-row table is four literals rather than one
(`familyRowsEgypt` + `Greece` + `Norse` + `BatchThree`), because one array
literal of sixty-eight eighteen-argument rows is what Swift's type checker
charges by the minute for; keep adding pantheon-sized pieces rather than
lengthening one.

**A thin-legged character needs a heavier clip carrier.** The satyr was the
one remake of thirty-nine that failed verification: base and LOD measured
1.60 m with the feet on the origin, but every one of its six clip carriers
measured 1.485 m with the feet 8 cm up. The carriers are decimated to 1,500
triangles at 128 px because the game reads only their tracks — and at that
budget the satyr's digitigrade goat legs collapse, which moves the mesh the
verifier measures. `--clip-tris 3000 --clip-texture 256` builds it clean at
8.4 MB. Any future character whose legs, tail or wings are thin wants the
same; the default stays 1,500 for the other thirty-eight.

**Batch 3's families.** Egypt: Ra, Osiris, Ptah, Khnum, Nephthys, Ma'at,
Serqet, Taweret, Anhur, Bes, Medjay, Cobra Priestess. Greece: Hera,
Hephaestus, Demeter, Dionysus, Aphrodite, Nike, Achilles, Atalanta, Siren,
Nymph. Norse: Baldr, Frigg, Surtr, Njord, Idunn, Sif, Ullr, Vidar, Fenrir,
Bragi, Einherjar, Shield Maiden, Light Elf, Dark Elf. Every design is
described, never named as a likeness; every concept is an A-pose with the
weapon against the leg and both feet showing, the rigger's two demands.

## Rome and the Jade Court's meshes, made in an afternoon (2026-09-11)

"Don't wait till tonight to make the new meshy characters. Just do it now?"
Gemini was capped, so the concepts were not painted; the twenty went to Meshy
as **text-to-3D** from the concept script's own sentences (`tools/batch/
text_wave.py`: an A-pose prefix, the description after the painter's framing,
the standard negative prompt, 600 characters at most, a balance check per
launch against the floor plus what the launched ones still owe). Twenty
launched between 12:50 and 13:10 UTC; the local pollers died mid-pipeline and
the tasks ran on at Meshy's end, so `meshy.py status` refreshed the manifests
and `resume_wave.sh` finished them. The wave cost 1,063 credits and left
2,133, above the 2,000 floor.

**Eighteen shipped.** Sixteen rigged characters — Mars, Minerva, Pluto,
Diana, Mercury, Bellona, Centurion, Gladiator, Vestal, Sun Wukong, Nezha,
Guan Yu, Chang'e, Nüwa, Fox Spirit, Jiangshi — at 9,000 triangles with the
LOD and seven clips, and the two dragons (the Azure Dragon and the Dragon
King) as unrigged meshes through `prop.py`, moved procedurally like the
Hydra. The sheets were looked at: robes split between the legs in the attack
clips as every robed family's do, Mercury's caduceus and Guan Yu's guandao
stretch on the carrier meshes (the sheet renders a clip file's 1,500-triangle
carrier; the game animates the 9,000-triangle model), and nothing was marbled
or the wrong size.

**Two refused.** Meshy's rigger returned "Pose estimation failed" for Neptune
and the Terracotta Soldier, twice each, a failed POST charging nothing. Their
refined meshes were rendered: both hold a pole weapon out beside the body,
the arm bent away and the shaft reaching the ground a stride from the foot,
which the pose estimator reads as a third leg — Guan Yu's guandao rigged
because it stands tight against him. The families fight as Poseidon and the
sandstone sentinel (`FamilyRow.standIn`, new: a stand-in per table row) until
a remake is paid for. The `_v2` prompts are written (a short trident or sword
held point-down flat against the outside of the thigh, both arms straight
down with a gap, no cloak; the negative prompt names polearms, spears,
staffs, a weapon beside the body or touching the ground, cloaks and capes);
a preview is 20 credits and can be judged before the refine, rig and clips
(36 more) are spent, and two of everything would end the balance near 2,021.
The launch was held for the owner's word: it is his last hundred credits over
the floor.

**Two faults in the shipper, found by this wave.** A clip file's mesh is a
1,500-triangle carrier for the skeleton and the clip, and `mesh.py` grounded
each clip AFTER that reduction and measured its height on it. At that budget
a small shell collapses outright: Diana's boots went, the carrier's lowest
point rose 17 cm, the checker refused her ("feet at y=0.168") and a clip
grounded on that carrier would have sunk her 17 cm into the floor; the
Gladiator (5.6 cm), Nüwa (1.1 cm) and the Fox Spirit (a 5 cm crown) failed
the same way. Now each clip is grounded and measured on the full mesh first
(`build(..., carrier=True)`, `verify(check_bounds=False)`). The second: the
grounding took the lowest vertex of the whole mesh, and the Fox Spirit's nine
tails, weighted to a thigh, swing 24 cm below the floor in her idle, so every
clip stood her that far in the air. `character.ground_animation` now grounds
on the feet (the vertices a foot or toe joint owns) while the pelvis stands
above 45% of its rest height, and on the body with the legs left out when
the figure lies down — a corpse grounded on its soles would sink Pluto's
robe 16 cm, and a corpse grounded on its lowest vertex floated the Fox
Spirit 55 cm, her tails being weighted to a thigh that a fall turns flat.
Measured across the wave, the rule moves no standing clip of any other
family and a death clip by a few centimetres at most. Families shipped
before this day were grounded the old way; one whose tail, hem or weapon
hangs lowest in most frames of a clip floats by that much, and a reship
fixes it.

## The angled arena frame, and what "the Summoners War feeling" is made of (2026-09-11, late)

The owner, with the CI's arena frame of an enemy's turn: "How can you give
me a screenshot of the battleground being angled and not see it? HOW can we
be different than Summoners War but with the same feeling? How can we
display the battleground? Summoners War is the only style gacha I've ever
truly loved because of the gameplay."

**What the frame was.** Not the home camera and not a bug in it: the fixed
camera's skill shot. Since the fourth playtest the fixed mode answered a
special, an ultimate or a killing blow with a hard CUT to a composed angle
on the caster — a three-quarter medium over a player's shoulder, a face-on
shot of an enemy — held for the clip and cut back (`CameraDirector.cut`).
The arena frame caught Heimdall's buff from that shot: the camera standing
left of the team looking across at the far right of the enemy row, the
tiles running diagonally, both rows swung round. A composed angle is a
different view of the floor, and that is what the owner sees first. It was
seen here, written off as "the push toward Ptah's ultimate" and sent;
neither the diagnosis nor the sending was checked. Rule 2 exists for that.

**What Summoners War actually does with its camera** (from playing it, not a
site — the wiki is refused by the network policy): one angle for the whole
fight, three-quarter from behind the player's side and a little to the
right, elevated. On a second or third skill the camera ZOOMS toward the
caster and back, and for an awakened monster's third skill a portrait
cut-in flashes over a darkened field; some skills darken the ground and
light the caster. The angle never changes. Not on an enemy's skill, not on
a kill, not on a boss. The floor is never seen from another side, which is
why the player's eye never has to re-find the field. The genre's other
big ones do the same (Epic Seven zooms and cuts to a 2D animation; Raid
zooms and shakes); none of them orbit or cut to a new angle in the default
view.

**The fix.** `CameraDirector.zoom` replaces the cuts in the fixed mode: a
dolly along the home line of sight to the point on the subject's own
sight line that stands the wanted distance back — the figure 52% of the
frame tall for a special, 44% for an ultimate, 60% for the victim of a
killing blow — eased in over 0.22 s, held for the clip, eased out over
0.30 s. The camera slides parallel to itself, so it recentres the subject
without a pan and every frame of the move is the home framing at a
different distance; the move never dollies out past home, so a boss framed
from 25 m gets a modest step and not a retreat. The cinematic toggle keeps
the authored moves for whoever wants them. `cutSide` went with the cuts.

**Different from Summoners War, with the same feeling.** The feeling is
made of things the player does and reads, not of what the art looks like,
so every one of these stays exactly as the genre has it: one fixed angle
for the whole fight, from behind and slightly right; two rows that face
each other with every enemy alone against the floor where a finger finds
it; the attack bar with portraits at the top; a health bar under every
figure; tap the enemy, tap the skill; a zoom and a cut-in on the big
skills; a flash and a number on every hit; ×1/×2/×3 speed and auto. What
is ours is the world those rules play in: a real place per pantheon (a
temple floor between columns, a hall of the dead, a mead hall) with the
realm painted behind a parapet instead of a disc in a void; bosses that
stand beyond the far edge on a breach; painted, detailed figures at 9,000
triangles; the cream-and-gold temple UI; five pantheons with their own
banners and chapters; the Hall of Ka, the Labyrinth, the living island.
The player should be able to say "it plays like Summoners War" and "it
looks like nothing else" in the same breath.

**How to display the battleground** — the three ways, and the one to keep:
1. A disc in a void with the environment painted far behind (the genre's
   dungeon look): tried first and photographed as "a tilted disc in a
   void"; rejected.
2. A real floor with the environment modelled around it — the 44 m arena
   slab with a parapet at the far edge, the painting above it, props at
   the frame's edge (the current stage): keep. It reads as a place, its
   tiles are square to the screen from the home angle, and with the
   camera's orientation now fixed the tiles never run any other way.
3. The same slab with a quieter floor: the flagstones two metres rather
   than one and the joints at lower contrast, so the pattern stops
   emphasising perspective under the figures, plus a darkening toward the
   far edge (the genre's floors are low-contrast, and the figures carry the
   detail). This is the next step for the stage and needs a texture pass
   (Gemini is capped; the tile textures can be reworked in PIL from what
   exists) — a texture change, no camera change.

## The bars under the feet: unit plates the genre's way (2026-09-11, night)

The owner, with a crop of the arena frame: "the enemies' health bar is just
gray. It also looks big and blocky. I want it nicer looking and more fluid,
not so cartoony, like Summoners War. WITH the attack bar (attack speed /
turn order bar like Summoners War) under it."

**What the gray blocks were.** Not the enemies' bars — the player's own.
`UnitNode` drew every bar as three SceneKit planes on a billboard 0.34 m
above the head, 1.15 m wide: a light hairline, a black plate, a green or red
fill. From the camera behind and above the team, a bar over a player's head
projects onto the floor between the rows, right at the enemies' feet, so the
owner read them as the enemies' bars; lit by the scene and softened by the
bloom and the 2× multisampling, the green fill came out gray-teal, and at
that size the hairline edge made them blocks. The enemies' own bars were the
small red-brown ones over their heads. A bar drawn as geometry in the scene
can never be crisp, never the same size in both rows, and never sit where the
genre puts it without colliding with something.

**What Summoners War draws** (from playing it; the wiki is refused here):
under each monster's feet, in screen space at a constant size whatever the
row — a slim green health bar with a rounded dark track and a lighter top
edge, damage showing as a pale segment that lingers a beat and then drains;
under it a thinner light-blue ATTACK BAR that fills as the monster's turn
approaches and flashes when it is ready; the buff and debuff icons in a row
above the health bar; the element/level mark at the bar's left end; the
acting monster and the targeted enemy picked out with a marker. Both sides'
health bars are green — the row tells you whose it is — and the bars never
scale with the camera. Epic Seven and Raid do the same in their own dress:
the unit plate is a screen-space HUD element, not a scene object.

**The options.**
1. Keep the 3D planes and draw them better — a Core Graphics texture with
   a gradient and rounded ends on the same billboards, unlit, no depth.
   Crisper, but still scaled by distance (the far row's bars 30% smaller),
   still bloomed, still above the head or else on the floor plane under
   the feet where a foot occludes it.
2. A SpriteKit overlay on the `SCNView` (`overlaySKScene`, the mechanism
   Apple's own SceneKit samples use for a HUD): one plate per unit, in
   points, positioned every frame from `projectPoint` of the unit's feet.
   Crisp at any distance, constant size, gradient fills from Core
   Graphics, the fill and the attack bar tweened with `SKAction`, the
   status tiles and the matchup arrow in the same plate. This is what the
   genre does.
3. SwiftUI views over the scene driven by projected positions published
   from the render loop: the same look, but sixty layout passes a second
   through SwiftUI for ten units, and the positions a frame late.

**Chosen: 2.** `UnitPlateOverlay` (an `SKScene` in `BattleSceneView.swift`;
no new file, the project's synchronised group does not pick one up) holds a
`UnitPlate` per non-boss unit; the view's coordinator is the
`SCNSceneRendererDelegate` and calls `BattleSceneController.layoutPlates`
in `willRenderScene`, which projects each node's feet and stands the plate
12 pt below them (`projectPoint` gives view points with the origin at the
top on iOS; the overlay's origin is at the bottom, so y is flipped by the
scene's height). The plate: a 64×5.5 pt health bar (76×8 in the first run, which the owner loved and called too big) (a dark rounded track, a
green gradient fill with a light top edge, amber under 30%, a cream trail
that waits 0.35 s and drains after a hit), a 64×2.5 pt attack bar under it
(light blue, tweened over 0.45 s to the engine's value after every turn,
gold and pulsing at 100%), the element pip at the left end, the status
tiles above (13 pt, six at most, the same `StatusIconRenderer` pictures)
and the matchup arrow at the right end; a gold rim pulses on the acting
unit; the plate fades with a death and back with a revival. `UnitNode`
keeps its 3D bar code but hides it the moment a plate is attached, so the
island and the Hall of Ka, which have no overlay, are untouched. The
engine's attack bars reach the plates three ways: `syncPlates` from the
view model when playback settles (the actor back at zero, everyone else
advanced), the `attackBarChanged` event when a skill pushes or pulls one,
and the actor's bar shown full as its turn begins. A boss keeps the HUD's
bar and no plate. The nodes the render thread reads are snapshotted under
a lock whenever they change.

**Why green for the enemies too.** It is the genre's convention and the
owner asked for the genre's bar; whose unit it is reads off the row, and
the matchup arrow on a player's turn already marks every enemy. The red
fill of the first build was the one thing that made an enemy's bar look
like a warning rather than a health bar.

## Night 3: the authorised batch, painted (2026-09-12, 00:26–01:00 UTC)

The routine (`trig_01VJjUcbfKs8vRHiC1qHtAH7`) ran the one Gemini batch the
owner authorised on the evening of 2026-09-11 ("finish with that $32 worth
of art you need and then stop for now until I can figure out costs") and
nothing else. 263 images painted, in this order:

1. The cream menu kit, 2 images, first roll each: `ui_panel` (cream marble,
   a thin gold frame, scrolled acanthus corners reaching 95 px in) and
   `ui_button_dark` (a cream plate, gold border, 19 px gold ends). The
   caps in `Theme.swift` are 98 and 22, `paintedPanelMinimum` 165, and
   `Chrome.awaitingCreamRepaint` is empty: the whole kit draws.
2. Rome and the Jade Court's realms, 6: the two banners (a war god with
   the eagle standard, a goddess with an owl and a sea god with a trident;
   the Monkey King on a cloud before a jade gate with the azure dragon,
   the boy on fire wheels and the long-bearded general) and the four
   chapter backdrops (the Forum at midnight, the Colosseum's sand, the
   peach orchard, the dragon gate under the sea). All six looked at; no
   real face among them.
3. Batch 4's 20 concepts (one lane failure, Sun Wukong, retried). All
   original stylised figures; the board was checked for likenesses.
4. Batch 4's 100 base cards (one lane failure retried; Mercury's five
   repainted once because the painter kept the concept's grey ground and
   boxed the figure). Six families came back full-figure on the dark
   ground instead of the portrait crop — Neptune, Mercury, Vestal,
   Chang'e, Jiangshi, the Terracotta Soldier — usable, not the same crop
   as the other fourteen; a re-roll is five images a family.
5. Batch 3's 130 awakened cards, no failures.

No quota error at 265 requests, so the 250-a-day figure is not the
hard limit it was taken for; no spill-over routine was needed. Every
batch-3 and batch-4 family has its five cards now: all twenty of Rome and
the Jade Court join the gacha pool, both banners are offered, and batch
4's 70 awakened cards are the one thing left unpainted. The Meshy steps
found their manifests and skipped (18 shipped, Neptune and the Terracotta
Soldier refused, balance 2,133). Gemini is off again until the owner's
word.


## Relics designed, and the rune management system (2026-09-12)

The owner's two asks, verbatim: "1. We need actual relics designed (our
runes) 2. We need a full rune management system like summoners war". Rule 2
says research first, so this section is the research, the gap list, the
options and the choice, written before the first edit.

### What Summoners War's rune system is, screen by screen

From memory of the game and its guides — the data sites (the wiki, the
fan-run rune calculators) are refused by the network policy, so nothing
below was copied from a page; where a number is Summoners War's, it is the
number as remembered, and where it is ours it says so.

- **A rune is an object.** Six slots in a hexagon around the monster, slot
  1 at the top and clockwise. Each slot's rune has its own silhouette — a
  player tells the slot from the shape before reading the number — the set
  is an emblem engraved on the stone with a colour of its own, the rarity
  (the number of sub stats it dropped with: Normal 0, Magic 1, Rare 2, Hero
  3, Legend 4) is the frame and the name's colour (white, green, blue,
  purple, orange), the grade is a row of stars, and the level is "+N".
  Every list, every drop, every slot on the monster shows that one icon.
- **Slots 1/3/5 carry fixed flat mains** (ATK, DEF, HP) and 2/4/6 roll
  theirs (2: HP/ATK/DEF % or SPD; 4: + CRIT Rate/DMG; 6: + ACC/RES). Ours
  already do this (`Relic.fixedMainStat`, `allowedMainStats`).
- **Sets are 2-piece stat sets and 4-piece effect sets**; the effects that
  define the game are Violent (extra turn), Swift, Vampire, Despair (stun),
  Will (immunity), Nemesis, Shield, Revenge, Destroy. Ours: sixteen sets,
  eight stat and eight effect — Wrath is Violent, Zephyr is Swift, Styx is
  Vampire, Nemesis, Fates (Shield), Vigil (Revenge), Chains (a slow
  Despair), Titanfall; Will and Destroy have no equivalent yet.
- **Power-up** to +15, a chance of failure that rises with the level and a
  cost either way; a sub stat at +3/+6/+9/+12 (new while under four, then
  one grows); the main stat's jump at +15. Ours since 2026-09-10.
- **Grindstones and enchanted gems** from the Rift raids: a grindstone adds
  to one sub stat within a range set by the stone's rarity (Legend SPD +4–5,
  ATK% +7–10, as remembered); a gem replaces one sub stat with a chosen
  stat at a rolled value (Legend SPD 8–10, ATK% 11–13), one gemmed sub per
  rune, re-gemmable. This is the endgame's rune work and we have none of it.
- **Manage Runes** (the inventory): filter by set, slot, main stat, sub
  stats, rarity, grade, equipped state; sort by grade, level, set, slot, main
  stat, efficiency, recent; multi-select sell with the total; lock; a
  rune's card with Power-up, Grind, Gem, Equip (choose a monster), Sell.
  Ours has slot, set, unequipped, four sorts, select-and-sell, lock,
  power-up, reappraise, change (only for a worn relic).
- **The drop**: after a battle the rune appears as a card with its stats
  and two buttons, Sell and Get. Ours lists it on the chest's shelf as a
  glyph on a plate; the first look at a new relic is the inventory.
- **Rune removal costs mana.** Deliberately not copied: it is friction the
  owner never asked for and the genre's players resent.
- Epic Seven's gear adds a "gear score" and a reforge at +15; Raid's
  artifacts add ascension. Neither is worth a system of its own here;
  the efficiency dial already is a gear score.

### What we have and what is missing

| Summoners War | Pantheon before this pass | After |
|---|---|---|
| A rune is an object with a shape per slot, an emblem per set, a frame per rarity | an SF Symbol in a cream tile | 96 rendered stones, six rims, sixteen emblems (`RelicIcon`) |
| Rarity by sub-stat count, coloured everywhere | none; sub count followed the grade | `RelicQuality` Normal…Legend, rolled by weights per grade, the rim and the name's colour |
| Grindstones and gems from raids | none | whetstones and gems in three tiers, from raids, Hell bosses, the deep Labyrinth and the Tower; Grind and Gem on the relic's card |
| Filter by main, subs, rarity, grade | slot and set only | a filter sheet with every axis, an active-count badge |
| Sort by set, slot, main | efficiency, grade, level, newest | + set, slot, main stat, quality |
| Select all / sell by rule | tap each | "All shown" on the selection bar, with filters that make it a rule |
| A rune card at the drop with Sell / Get | a glyph on the shelf | tap the spoil: the card, Sell / Keep / Lock |
| Equip from the inventory | only from the unit's slot | "Equip on…" from any relic's card: the roster, the delta, Equip |
| Power-up to +N | one tap per level | "Power up to +3…+15" with the bill and the rolls summarised |
| Unequip all | one at a time | Unequip all on the unit sheet |

### The art: three ways to make a relic look like one

1. **Gemini paints them.** The best possible look — a painted stone per
   set with a real emblem. Paused: the owner's cap is $10 a month and
   nothing calls Gemini without his word for the batch. If he gives it,
   the batch is small: 16 emblems on black plus 6 stone shapes on black
   (22 images, about $3 at the pro price; 96 finished stones would be
   about $12). Everything built below keeps working with painted files
   dropped in under the same names.
2. **Rendered here, shipped as PNG.** `tools/relic_art.py` draws every
   stone in Python — the slot's silhouette, a bevelled gem-cut edge lit
   from the top left (a distance-transform normal map, the same idea as
   the plates' art), the set's colour with a stone grain and a gloss, the
   set's emblem engraved in gold — and ships `relic_<set>_<slot>.png` at
   320 px (the largest it is ever drawn is 110 pt), `relic_rim_<slot>.png`
   as a template the app tints with the quality's metal, and
   `relic_emblem_<set>.png` for chips and lists. The look can be judged
   HERE on a sheet before anything is committed, which no SwiftUI drawing
   can be (nothing compiles in this environment; a wrong path is a
   25-minute CI round trip). About 5 MB of bundle for 118 files.
3. **SwiftUI `Path` drawing.** Resolution-independent and free of bundle
   cost, but sixteen emblem paths and a bevel written blind, seen for the
   first time in a CI frame.

**Choice: 2, with 1 offered.** The rendered stones are the best result
this environment can verify, and the painted upgrade is a $3 batch away
under the same file names. The rule-1 sheets of the stones are in the
report.

The design, so the code and the art agree:
- **Shape by slot** (the ring's order, slot 1 at the top): 1 a crystal
  (the flat-ATK slot, a blade), 2 a medallion (circle), 3 a shield (flat
  DEF), 4 a hexagon, 5 a vial (a drop, flat HP), 6 a tablet (a cut-corner
  cartouche). Six silhouettes a thumb tells apart at 30 pt.
- **Emblem and colour by set**: Fury a flame on crimson, Aegis a shield on
  steel blue, Bulwark a keep on green, Zephyr a wing on teal, Thunder a
  bolt on amber, Ruin a burst on plum, Oracle an eye on violet, Wards a
  seal on indigo, Ichor a chalice on blood-orange, Wrath a triskelion on
  magenta, Styx waves on black water, Chains two links on iron, Fates a
  wheel on silver, Nemesis scales on dark red, Titanfall a mountain on
  earth, Vigil a return arrow on bronze. A light stone (Fates) takes a
  dark emblem so it reads.
- **Rim by quality**, the app's rarity metals: Normal grey, Magic green,
  Rare blue, Hero purple, Legend gold — the same five the cards wear, so
  nothing new has to be learned.
- **Stars are the grade, "+N" the level**, drawn by SwiftUI under and over
  the stone; the card's name is coloured by quality ("Legend Fury Relic").

### The management, and the numbers

- **Quality** (`RelicQuality`, an Optional on `Relic` so old saves decode;
  a relic without one is read off its sub count and level). Rolled at the
  drop by grade, in percent Normal / Magic / Rare / Hero / Legend:
  1–2★ 45/35/15/5/0, 3★ 30/35/22/10/3, 4★ 18/32/28/15/7, 5★ 10/26/32/21/11,
  6★ 6/22/34/26/12. Hell tiers floor a drop at Magic, raids at Rare.
  Summoners War's Legend rate at its top dungeon is lower (about one in
  twenty, as remembered); ours is one in eight because there is no cash
  shop pacing it. The sub count IS the quality (0–4); power-up adds while
  under four, so a Normal fills to four subs by +12 exactly as the genre
  has it. Reappraisal keeps the quality and rerolls from it. Mirrored as
  `QUALITY_WEIGHTS` in `balance.py` (`--relics`).
- **Whetstones and gems** (`RelicStone`): three tiers, Rare / Hero /
  Legend, one kind of each, NOT per set (Summoners War's per-set
  grindstones multiply the inventory by twenty and are the part of the
  system its players complain about). A whetstone adds to one sub stat a
  bonus of 0.25–0.45 / 0.40–0.65 / 0.60–0.90 of a 6★ sub roll's base
  (`subStatBase(kind, 6)`: SPD 6.3, so a Legend whetstone is SPD +3.8–5.7,
  the genre's +4–5); re-honing keeps the better bonus. A gem replaces one
  sub stat with a chosen kind at 0.85–1.05 / 1.00–1.25 / 1.20–1.50 of that
  base (Legend SPD 7.6–9.5, the genre's 8–10); one gemmed sub per relic,
  the same one can be gemmed again, and a gem clears that sub's whetstone
  bonus. Costs in drachma: whetstone 4,000 / 9,000 / 16,000, gem 6,000 /
  14,000 / 24,000. Sources: the Apep raid (a Hero whetstone 70%, a Legend
  25%, a Hero gem 35%, a Legend gem 12%), a Hell boss (a Rare whetstone
  35%, a Rare gem 15%), Labyrinth B7+ bosses (a Rare whetstone 25%, from
  B10 a Hero 10%), the Tower's 50/75/100 milestones, the Testing stall (a
  crate of ten of each, free, while `testingPacksEnabled`) and the laurel
  stall (a Legend gem). Stored as `Player.relicStones: [String: Int]?`.
- **The inventory**: `RelicFilter` (slots, grades, qualities, main kinds,
  sub kinds — every ticked sub must be on the relic, that is what a hunt
  is — worn state, locked), a sheet of chip rows, the bar showing how many
  axes are live; the set chips stay as the quick filter. Sorts gain set,
  slot, main stat and quality. "All shown" selects every unlocked, unworn
  relic in the current list.
- **The drop card** (`RelicDropCard`): a tap on a relic's spoil tile on
  the victory shelf; Sell (with the value), Keep, Lock and keep. An auto
  run banks everything as before.
- **Equip on…** (`RelicWearerPicker`): the roster by power, the delta
  table for the one tapped, Equip. **Power up to +N**: the store attempts
  until the level or the drachma runs out and hands back every outcome for
  the summary line. **Unequip all** on the unit sheet's toolbar.
- **Removal stays free**, on purpose (above).

Verification: the CI tour's relic screens (2 detail, 11 relics, 17
relic_picker, 19 relic_powerup, 20 victory, 21 collection_stage) plus two
new steps, 22 `relic_drop` (the card) and 23 `relic_filter` (the sheet);
`balance.py --relics`; the unit tests for quality, reappraisal, stones and
the save fields.

### What shipped (2026-09-12, afternoon)

Built whole, as the section above lays out, and checked with
`swiftcheck --members --types` (clean; it caught two `StageRewards` calls
with `stoneChances` out of memberwise order, which would not have compiled)
and `balance.py --relics`:

- `tools/relic_art.py` and its 118 PNGs (5.3 MB). Two sheets were judged
  here before shipping: the first cut had ten percent of grain and
  photographed as camouflage, and its emblems sat small in the crystal;
  the second (a broad marbling at six percent and a fine tooth at two and
  a half, the emblem fitted to 98% of the inner box) is what shipped. The
  30-pt row of the size strip still tells slot, set and quality apart.
- `RelicQuality`, `RelicStone`, `Relic.quality/honed/gemmed` (all
  Optional), `Player.relicStones`, `StageRewards.stoneChances/qualityFloor`,
  `StageOutcome.stonesEarned`, `Grant.stones`; `RelicService.rollQuality`,
  `hone`, `engrave`, `gemKinds`, `stoneSpan`, `unequipAll`; reappraisal
  replays the level's rolls from the quality; the sell value rises a fifth
  per quality step; the starter's relics are Rare.
- `RelicIcon`, `RelicSetEmblem`, `RelicQualityTag`, `RelicFilter` and
  `RelicFilterSheet`, `RelicStoneSheet`, `RelicWearerPicker`,
  `RelicDropCard`; the inventory's eight sorts and "All shown"; the card's
  hero stone, quality tag, honing and gem marks, Power up to +N, Equip
  on…, Hone & gem; the slot tiles, the picker's summary, the optimiser's
  rows, the drop lists' chips and the chest's shelf all draw the stone.
- Sources: the Apep raid (stones at 70/25/35/12%, quality floored at
  Rare), Hell bosses (a Rare whetstone 35%, a Rare gem 15%, every Hell
  drop at least Magic), Labyrinth B7+ (a Rare whetstone 25%, from B10 a
  Hero 10%), the Tower's 50/75/100 milestones, the Testing stall's
  stonecutter's crate and two laurel items.
- Tests: `RelicQualityTests` (nine), two save round-trips, the crate.
- The tour: `relic_drop` (22) and `relic_filter` (23).

The expected bill, 6★, with the power-up odds: +3 14,400 drachma, +9
91,000, +12 170,000, +15 299,000 (`balance.py --relics`). A Legend 6★ is
one drop in eight at B10; a 3★ Legend one in thirty-three.

## The premium pass: seals, type, and the relic screens in the genre's shape (2026-09-12, evening)

The owner, on the relic pass an hour after it shipped: "1. The symbols on
the relics look like shit. It doesn't look premium. 2. The menus and UI
look overwhelming. Remember when I said research? 3. Can we make the UI
look and feel more premium? And maybe a nice cleaner font? Make things
size correctly too?" All three are right, and the second is a rule-2
failure: the relic screens were built as text rows because that is what
was there, not because that is what the genre does.

### What our own frames say

The twelve busiest tour frames on one sheet, read cold:

- **Bars carry five to eight controls** (the collection: two segments,
  six element chips, two menus, two buttons; the arena: four counters,
  two buttons and a four-item wallet). Summoners War shows the wallet in
  one place, large, and keeps a screen's bar to two or three controls.
- **Sentences on menus.** The Hall of Ka, the Labyrinth's cards, the
  halls' boss panels, More's settings and the chapter map all carry
  9-point paragraphs. The genre's menus carry numbers and icons; words
  come on a tap.
- **Ninety call sites of text at 7–9 points** (`body(7)` ×6, `body(8)`
  ×18, `body(9)` ×66, `numeric(7–9)` ×30), which after `fontScale` 0.9 is
  6.3–8.1 points on the phone. Apple's floor for legible text is 11; the
  genre's smallest label is about 11–12.
- **Numbers in a monospaced system font** — a developer's face, not a
  game's — and heavy system-serif titles that read as a default rather
  than a choice.
- **The painted marble frame on every panel**, corner ornaments included,
  so a screen of four panels has sixteen acanthus scrolls competing with
  its content. Premium is one ornate frame per screen and quiet cards
  inside it.
- **The relic inventory as text rows**: twelve rows of four sub-stat
  cells, a dial, a wearer's name and a set rail with sixteen worded chips.
  The relic card carries eleven lines of words before its buttons; the
  drop card five dials.

### What the genre does (from memory; the sites are refused here)

- **Summoners War's rune inventory is a grid of rune icons** — six or so
  a row, the icon alone with its stars and +level — and ONE information
  panel for the rune tapped: main stat, four sub stats, the set effect,
  who wears it, and two or three buttons. Filter and sort are two buttons
  at the top left. The monster's rune screen is the hexagon around the
  model with the set effects listed once. The power-up screen is the rune
  large in the middle, its stats at the right and one big button.
  Titles are a bold sans in capitals; nothing on a menu is a sentence.
- **Epic Seven's gear** is the same shape: an icon grid, a side panel, a
  gear score, one Enhance button. **Raid: Shadow Legends** sets its
  headers in a classical display face over a clean sans body — the
  precedent for a temple UI that is not carved-looking everywhere.
  **Genshin's artifacts** are icon-first rows with a detail panel, set at
  a generous rhythm; the premium feel there is restraint.

### The three levers, with the options weighed

**Type.** (1) Keep the system fonts: free, but the monospaced numbers
and the default serif are two of the three things that read as cheap.
(2) Bundle two OFL faces: **Cinzel** (Natanael Gama; Roman inscriptional
capitals, the lettering a temple actually wears) for titles, display and
buttons, in capitals with tracking, never under 12 points; **Manrope**
(Mikhail Sharanda; a clean geometric sans with true tabular figures) for
every word and every number. About 700 KB in eight static instances cut
from the variable files with fontTools, registered at launch with
CoreText (`CTFontManagerRegisterFontsForURL`), so the generated
Info.plist is untouched; a missing file falls back to the system face.
(3) A commercial temple face (Trajan): not licensable from here.
**Choice: 2.** With it a **floor**: `Theme.body` never returns under 10
points, `numeric` under 10.5, `title` under 12 — the ninety tiny call
sites lift at once, and nothing else has to be found by hand.

**The seals.** (1) Gemini paints the emblems and shapes: about 22 images,
about $3, and Gemini is paused until the owner says so. (2) Filled
code-drawn symbols, which is what shipped: a shuriken, a road-sign
U-turn, a castle — clip art, as he said. (3) **Engraved line seals**: one
stroke weight for all sixteen, classical motifs, the engraving's shadow
and light on the stroke — an aspis of concentric rings for Aegis, a
Doric column for Bulwark, a torch for Vigil, a chalice for Ichor, a
spiral for Wrath, scales for Nemesis, a wheel for Fates, an eye for
Oracle, a bolt, waves, links, a mountain, three curls of wind, a flame,
crossed swords for Ruin, a ringed pentagon for Wards. Judged on a strip
and on the stones at 30, 44, 64 and 110 points before shipping.
**Choice: 3 now, 1 offered.**

**Density.** The relic inventory becomes the genre's grid: the stones at
48 points, seven or eight a row, one panel at the right for the relic
tapped, and the set rail sixteen emblem chips with a count and no word.
The card loses its paragraphs and gains one primary action, the rest a
quiet grid of small labelled buttons. The drop card loses its five dials
for one line. The filter's slot chips are the slot silhouettes, its set
chips the emblems. One painted frame per screen; plain cards inside.

### What this pass does NOT do, said plainly

The other twenty screens keep their layouts and get the fonts and the
type floor only. The wallet strip, the five-control bars and the
sentence panels are the next pass (task #50, the 104 audited findings),
one screen at a time against the genre's own, with a frame looked at for
each. Saying so here rather than leaving a lesser version silently.

### What shipped (2026-09-12, evening)

On `main` at the fourth run of the day (d3765fd, then 7f49cf0 for one
fit): the seals, the two faces registered on the simulator ("[Fonts]
registered 8 of 8 bundled faces; Cinzel true, Manrope true" in every
step's console), the floor, and the grid inventory. The first grid frame
had the panel's fixed stack at 352 points in a 330-point frame, which
pushed the whole screen up under the strip; its words scroll now and its
buttons stay. Every one of the twenty-four frames was looked at with the
new type; nothing clipped that did not clip before. Left for the next
pass, by name: the wallet strip on every screen, the five-to-eight-control
bars, the sentence panels on the Hall of Ka, the Labyrinth, the halls,
More and the chapter map, and the painted frame on every inner panel.

### The ring, after "look how ugly this is" (2026-09-12, night)

The crop the owner sent was the unit sheet's relic ring: six bordered
tiles, each with a slot badge on one corner and a level badge on the
other, a stone a third of the tile, three lines of seven-point text under
it, a dashed placeholder circle, and three footers of instruction. The
genre's rune hexagon is bare stones in quiet sockets joined by one thin
line, the numbers read on a tap. So: a socket is a soft recess with no
border, the stone fills three quarters of it with its level on its own
corner, an empty socket shows the slot's silhouette as a ghost with the
number on it, the sets are emblem chips with a name and nothing else, and
the footer is the three figures. The same tile is the collection's plate
and its stage layout.


## The loading screen (2026-09-12, night)

The owner: "a loading screen that's like an art piece of the game,
something like what Summoners War does before the game starts". What the
genre does at launch, from memory: Summoners War shows its publisher's
card, then a full-bleed piece of key art with the game's logo, a bar
along the bottom with a percentage and a tip, then "Touch to start";
Epic Seven an animated logo, then title art with the same tap; Genshin a
logo, then its door. The tap is a server handshake — the game connects
while the art is up — and this game has no server, so the screen here is
the art, the name, and a bar tied to real work, held long enough to be
seen.

The art: Gemini is paused, so the candidates were the twelve paintings
on one sheet. The five summon banners are key art in all but name — Zeus
under lightning over his temple, Anubis rising in the Duat, the three
Norse on a longship under the aurora, the Roman three at sunset, Wukong
on his cloud — and the first mock on the Olympus banner read as a title
screen at once. Two things the mock settled: the crop is anchored to the
painting's TOP (a centred 16:9 crop of a 16:10 banner took Zeus's face
and put the name across it) and the name sits at half height on the dark
clouds under the figure, with the bar at 87%. The five banners take turns
so the screen is not the same twice running.

Chosen: a SwiftUI `LaunchView` over the game — the painting faded up from
ink with a slow push, a vignette, embers on a canvas, PANTHEON in Cinzel
with a gold rule and the Fates wheel, the five pantheons, a thin gold bar
on four named steps, a tip, the version — held no shorter than 2.6 s and
dissolved over 0.9 s; the system launch screen is the same ink so the
first frame and the fade agree. Offered: a painted key art of its own
(one Gemini image, about fifteen cents) under the same file name.


## One stone, the set reference, and the key art (2026-09-12, night)

The owner, with the collection screen in front of him: "how much would
it cost to have Gemini design the relics? They just look so sloppy, and
the UI for the relics look weird since they are all different shapes.
They should be all the same shape but have the different symbols. Where
can I see what each type of relic does and how many of each relic I need
to apply before the effect takes place? All this info should be on the
rune management system. The relic management system is good, but I need
it SUMMONERS WAR LEVEL." And "Do it" for the painted key art offered the
night before.

### The shape

What the genre does, from memory: Summoners War's runes do differ by
slot — each of the six slots has its own silhouette, and a player learns
to read the slot off the shape — which is where the first cut came from.
Epic Seven's gear differs by TYPE (weapon, helm, armour, necklace, ring,
boots), which is the same idea. Raid's artifacts likewise. The owner has
seen ours and calls the six shapes weird, and his word decides: one
shape, sixteen seals. The cost of that is that the slot must be said
some other way, and the genre's other way is a number: a badge on the
stone's corner (`RelicIcon.showsSlot`), and on the ring the socket's
place, which never needed a shape.

Which shape: a circle reads as a coin and fights the set emblems, which
are round chips; a rounded square is a tile and cheap; a shield is one
set's own seal; a hexagon standing on a point is the ring's own figure
(the six sockets sit on one), nests at 38 points, and reads as a cut gem.
Chosen: the hexagon, corners softened 0.09, the same bevel, grain and
gloss as before, sixteen files instead of ninety-six and one rim instead
of six. `tools/relic_art.py --ship` writes the sixteen and clears the
per-slot files; the sheet was judged at the app's four sizes before
shipping.

### Where a set's effect is read

The genre's rune screen has a set-effect list one tap away, with the
pieces each takes; ours had the effect only on a relic's own card and the
rail's caption. Now: `RelicSetsSheet` — every set in two columns (stat
sets of two, effect sets of four), its seal on a disc of its colour, its
name, a "2 pieces" chip, the effect in a sentence, and how many of it the
bag holds and the roster wears. Opened from "Set effects" beside the
rail's caption, from the inventory's menu, and from the unit sheet's sets
row; opened from a unit it counts that unit's pieces per set, lit where
the set is complete, so "one more Fates" is read rather than worked out.
The unit sheet's sets row is progress chips — "Fury 2/2" in gold, "Fates
1/4" dim — where it showed completed sets only, and the footer's "In
progress" line went with it. The grid cells wear the wearer's face on a
worn relic (the genre's mark) and the slot number; the card prints the
+15 main stat beside the next level's.

### The key art

One Gemini image, authorised: 16:9 at 1920×1080, the five pantheons'
gods described and not named — a thunder god raising a bolt at the
centre, a jackal-headed god with crook and flail, a one-eyed all-father
with two ravens, a Roman war god with an eagle standard, a monkey king
on a cloud — on a summit over a sea of storm cloud at dawn, the lower
half asked to be dark for the name. The painter delivered exactly that
in 22 seconds and lettered the eagle's plaque anyway ("ROMAN"), which
was dissolved into the gold here rather than re-rolled. Three mocks
placed the wordmark: at 0.50 of the height it crossed the thunder god's
waist, at 0.64 it crowded the bar, so it sits at 0.58, on the summit's
dark base. Shipped as `launch_key_art.jpg` (363 KB); the five banners
take turns only in a bundle without it.

### The cards, from the team screen

Two more notes on a screenshot of the team screen: "how do I know leader
skills if there's no symbol for it on the character?" and "why can I not
see how many stars the mon has. Maybe the borders are excessive if it
blocks the picture + stars." The star row was there — on a dark capsule
at the foot of the card — but the carved frame texture was an `.overlay`
on the whole card, drawn over it, gold on gold. Now the frame is drawn
under the badges and the stars, and only on cards of 90 points and up:
the reveal's and the unit sheet's carry it, the 76-point grid card and
the 58-point team card wear the grade's thin metal stroke, which is what
the genre's cards wear. A unit with a leader skill wears a gold crown at
the top right, under the lock.

### Painting the relics, the quote

Gemini is paused, and the owner asked what a painted set would cost. With
one shape it is one master stone (a hexagonal gem, cream-lit, no seal)
and fifteen `--ref` edits changing the colour and engraving the seal,
sixteen images at about fourteen cents on the pro model: about $2.30,
and $3–5 with the re-rolls a batch always needs. The emblems would then
be cut from the paintings for the chips. Not spent: it needs his word.
Meshy is the other painter: `POST /openapi/v1/text-to-image` is on its
API (read off the validation errors; an empty body creates nothing) and
takes the same Google and OpenAI image models (`nano-banana-pro` is the
model the cards were painted with) billed in Meshy credits, whose price
per image is unknown until one is made. The balance is 2,133 against a
floor of 2,000, so a test costs room he set aside; his call.


## The campaign pays as it is walked: sets by road, and tributes (2026-09-13)

The owner: "I don't want to copy Summoners War, but I like how the
campaign has rewards as you complete it (like crystals, and scrolls and
things) and specific rune types depending on the area or level. How can
we do that without copying exactly?" Then: "go ahead and do it."

### What the genre does

Summoners War drops fixed rune sets per scenario area and pays crystals,
energy and scrolls on a stage's first clear, and never says in-game which
area drops what: players read a wiki. Epic Seven marks the gear set on
every map node and pays region rewards for full exploration. Raid rates
every stage out of three stars and pays a chapter chest when all of its
stages are three-starred; each chapter's stages drop a named artifact
set. AFK Arena stands chests on the campaign road itself, opened as the
road is walked. Milestone rewards and loot tied to place are the genre's
grammar, not one game's; what is ours is what the rewards are called,
where they show, and which set belongs where.

### What we had

A first clear paid divinity in the Labyrinth only; the campaign paid one
feat per chapter (100 divinity and a Pantheon scroll) and dropped relics
of any set. Every stage computed a one-to-three star rating from the
survivors and the turns taken, paid a quarter more drachma for three,
and forgot it.

### Chosen

1. **Two sets a chapter, by myth.** One stat set and one effect set, on
   every stage of the chapter at every tier: the Duat weighs and binds
   (Oracle and Nemesis; Wards and Styx at the western gates), Olympus
   arms (Aegis and Ichor; Thunder and Fates; Zephyr and Titanfall),
   Yggdrasil rages and chains (Fury and Chains, Gleipnir; Thunder and
   Wrath; Bulwark and Vigil, the wall and the watchman), Rome augurs and
   fights to the death (Oracle and Vigil, the augurs and the Vestals;
   Ruin and Titanfall, the sand of the Colosseum), the Jade Court rides
   the clouds (Zephyr and Ichor, the peaches; Wards and Wrath, the
   talismans and the havoc). Every one of the sixteen is on some road;
   eight are on two. The map prints the two as emblem chips over the
   road: "YIELDS · Oracle · 2 · Nemesis · 4 · Every relic that drops here
   is one of these." Considered and rejected: widening the sets on Hard
   and Hell (the tier already raises the grade and the quality floor;
   widening would blur the farm), and per-stage sets (a ten-stage chapter
   with ten targets is a wiki again).
2. **Stars saved.** The rating is a high-water mark per stage id, the
   tier's suffix included (`Player.stageStars`, Optional), drawn as pips
   under the medallion and in the list.
3. **Three tribute chests a road, at each tier.** The road's tribute by
   the third stage, the gate's by the boss, the realm's judgment beyond
   it when every stage holds three stars. What they pay is in
   `TributeService.payout` and `balance.py --tributes`:

   | tier | road | gate | judgment |
   |---|---|---|---|
   | Normal | 30 div, 1 Pantheon scroll | 60 div, 3 essence, 4★ Rare of the set | 120 div, 2 Mystical, 5★ Hero |
   | Hard | 50 div, 1 Pantheon, 2 essence | 100 div, 4 essence, 5★ Hero | 180 div, 2 Mystical, rare whetstone, 6★ Hero |
   | Hell | 80 div, 2 Pantheon, 3 essence | 150 div, 5 essence, rare gem, 6★ Hero | 250 div, 3 Mystical, hero whetstone, 6★ Legend |

   A Normal chapter's three are worth about 4.6 pantheon summons, Hell's
   9.1; twelve chapters over three tiers are 108 chests and 72 guaranteed
   set relics. The essence is the chapter's own, read off its boss
   stage, and the relic is one of the chapter's two sets at the tier's
   grade: the tribute pays more of what the road is for.
4. **The chest is the reward chest.** On the map, its concept painting
   keyed off the grey ground (`ui_tribute_chest.png`, no spend), standing
   in the lane the road is not in, shut with a lock, gold and pulsing
   with a mark when earned, grey with a check when paid. Its card opens
   the victory's own 3D chest, lid hinged the same way, on Claim, and
   lists what it paid with the relic drawn as a stone.

### Why it is not a copy

The rewards are tributes of the realm's god, not first-clear crystals;
the sets are shown on the map and chosen by myth rather than hidden and
arbitrary; the three-star track is Raid's shape and the road chests are
AFK's, and together with the names, the seals and the chest they map one
to one onto none of them.

## The stones painted (2026-09-14)

The owner: "Do the painted relics. I want those to look better." His word
for this batch; the cap stays ten dollars a month and the quote was
$2.30 to $5.

### What the genre's icons are

Summoners War's runes are painted gems: a saturated mineral with a gloss,
the set's symbol on the face, read at forty points in a grid of hundreds.
Epic Seven's gear is painted per piece with the set's icon over it; Raid's
artifacts likewise. None of them is a line drawing; all of them are one
painter's hand across the whole set, which is what makes a grid of them
read as a system rather than a pile.

### Three ways to paint sixteen stones

1. **Sixteen singles, each from its own rendered stone as the reference.**
   About $2.30. The seal is held to ours by the reference. The risk is
   sixteen slightly different hands.
2. **One sheet: the sixteen rendered stones on black as ONE reference,
   repainted as one image.** About 14 cents an attempt. One hand by
   construction; the painter keeps the positions, colours and seals of the
   reference. The risk is a cell that mutates, which is fixed by option 1
   for that cell alone.
3. **Meshy's text-to-image.** The same models for credits, at a price per
   image nobody has read yet, against a floor of 2,000 with 133 to spare.
   Not for a batch.

Chosen: the sheet, singles for the outliers. Black ground, keyed by
darkness and flood-filled from the border (a dark carve inside a stone
survives; the sprites of 2026-09-10 learned the same). The painting
supplies the surface and the code the cut: `tools/relic_paint.py` scales
each painted stone to cover the renderer's hexagon and clips it to that
hexagon, adds the renderer's edge line, and ships it under the same
`relic_<set>.png` name, so the tinted rim still fits and nothing in Swift
changes; the emblems stay the line seals, which are chips at twelve
points. Judged on the same sheet as the rendered stones, at the app's
four sizes, before shipping.

### What shipped (2026-09-14)

Three images, 42 cents. The sheet came back as one hand: sixteen faceted
gems, every position, colour family and seal where the reference put
them, on black. Two drifted — Ichor to lavender and Titanfall to obsidian
— and were re-rolled alone from their own renders (a copper chalice
stone and a brown mountain stone came back). Each stone was keyed off
the ground, scaled to cover the renderer's hexagon (3% over, so no
edge shows), clipped to it, given the renderer's edge line, and judged
on the same sheet as the renders at the app's four sizes before shipping.
`relic_art.py --ship` now leaves the paintings alone unless told
`--ship-stones`. `RelicSet.stoneHex`, the disc behind an emblem chip,
was left as it was: the chips are read beside the stones, not matched to
them, and a median measured off a faceted painting is the colour of its
shadows. The bundle grew 0.6 MB.

### The devices, after "as if they were drawn by a kid" (2026-09-14)

The owner sent the painted sheet back: "the symbols on the relics look
basic and shitty, as if they were drawn by a kid." True, and the cause was
mine: the seals were line drawings made for legibility at twelve points,
and a painter handed a stick figure paints a stick figure in gold. What the
genre's rune symbols are is sculpture — a device with mass, light and
shadow, like the face of a coin. So the fix was not a better drawing to
copy but a description to sculpt from: each set's subject kept and
written for a carver (`relic_paint.SYMBOLS`), and the shipped painted
stone given back as the reference with "keep the gem, replace the line
symbol with an ornate gold bas-relief of X". Fury was tested first and
came back a three-tongued flame in relief on the ruby; the other fifteen
followed in three lanes; Chains (a plaque that swallowed the stone) and
Wards (a coin that read like Aegis's medallion at thirty points) were
re-rolled once with "engraved directly into the face, no plaque, no coin".
Eighteen images, about $2.50, on top of the three before.

The chips could not follow the same road: cutting a device down to a
thirteen-pixel template makes a blob where the line seal stays a glyph
(measured on a sheet at 13, 16, 24 and 40 pixels). So the chips show the
painted gem itself, small, with the set's name beside it everywhere a chip
appears — the rail's count, the sets row, the map's YIELDS, the filter,
the reference — which is how the genre's set filters show the rune. The
loading screen's gold rule keeps the tinted line wheel (`lineSeal`).


## The chapter as a place (2026-09-14)

The owner, of the chapter screen: "looks so dumb. If we click on the basic
map onto a chapter, it should open a NICE looking map that has the stages.
Not a map and a list below. I want just a map that when I click on it, it
shows a pop up of the chapter and description/rewards (kind of like
Summoners War), but I like the high level map first, then chapter map."

### What the genre does

Summoners War's scenario screen is the region's painting filling the
frame with the stage nodes standing on it along a path; a tap on a node
opens a popup with the stage, its drops as icons, the energy and Start,
which leads to the team prep; difficulty tabs at the top; arrows to the
neighbouring regions; no list anywhere. Epic Seven and Raid are the same
shape: the map is the screen, the details are a popup. Ours was a
190-point strip of map over a header panel over a list of the same
stages — three views of one fact, and a form.

### Chosen

The world road stays as the high-level map (the owner likes it first).
A city opens the chapter full bleed: the stage's painting fills the
frame, shaded a little top and bottom so gold and cream read; the road
winds through the middle band (0.41–0.71 of the height) with larger
medallions and their pips; the tribute chests wait along the bottom of
the road (0.87) — one lane, so they never sit on a medallion and never
under the plates; the chapter's plate at the top left carries the realm
and name, the story line, the progress bar, Next and the YIELDS chips;
the tier chips and their one-line note sit at the top right; an arrow
at either edge walks to the chapter before or after, where the story
lets it, which replaces the chip strip (the Realms sheet still lists
every chapter, Rome and the Jade Court included, until the world
painting has their cities). A medallion opens the stage's popup over
the dimmed map: the stage and "Stage 4 of 5", the story line, the first
wave's enemies as cards, DROPS with the chapter's two gems first, the
relic chance and grade, essences, scrolls, drachma and the first clear,
your power against the stage's, "Team & runs" for the full briefing and
"Fight" for one run now. Considered and rejected: the popup as a sheet
(a sheet is a whole screen on a landscape phone; the genre's popup is a
card over the map, and the map should stay in view), and keeping the
list as a scrollable drawer (the list was the complaint).

### The map painted: the region from above (2026-09-14, afternoon)

The owner, of the full-bleed chapter: "I meant literally a map of like
the area. Not just a plain background with lines. Ask me questions to
clarify." Asked, he chose: painted terrain seen from above, the way
Summoners War draws a scenario area; paint Duat 1 first and judge it on
the finished screen before the other eleven; fit one screen; and for the
density pass, the small cards first.

One Gemini image at 21:9 (the phone's landscape content area is about
2.5:1, so the fill crops only 3% top and bottom): the Duat's first region
at dusk from a high oblique angle, one road unbroken from the lower left
to the upper right past five landmarks named in the prompt in story
order — the jackal gate, the reed river, the scarab court, the hall of
sentinels, the serpent's hall of scales as the boss's lair, largest.
The painter delivered all five in order. The medallions stand on the
landmarks and the chests on open sand by the road, at points measured
off the painting with a ten-by-ten grid (`ChapterMapArt.byChapter`) and
placed through the fill's crop, the island's and the world map's method;
the code road is not drawn on a painted map, since the painting has its
own. The tier chips moved from the top right to the top centre, where
the sky is, because the maps put the boss's lair in the upper right —
and the first frames showed them across the title plate: a 300-point
plate at the left and a 250-point row centred on an 852-point phone
overlap by 70 points. They stand in the strip's empty centre now
(`TierChips`, between the title and the Realms button, the genre's
top-bar tabs), Hard's and Hell's terms are the plate's last line (Normal
needs none), a tier shut on the chapter opened falls back to Normal
(`settleTier`), and the World button is gone: the chevron is the same
door, and the strip has to fit a 667-point SE with the three chips in
it (about 620 points with them, 700 with World). Fifteen cents. If it is right, the other eleven are one script and about
$1.60 more, each measured the same way: `tools/batch/chapter_maps.sh` is
that script, written and NOT run (every prompt is the Duat 1 template with
the chapter's own five landmarks in story order, the lair last), and
`python3 tools/mapgrid.py <map> --dots x,y … --chests x,y …` draws the
ten-by-ten grid and a guessed row of medallions on the painting so a
chapter's anchors can be checked before they are committed. The eleven
generated chapters have ten stages each, so their ten medallions stand on
the five landmarks and the road between them.

**The other eleven, the same evening.** The owner, of Duat 1's frames:
"I love it, go ahead and make the other maps. Then I will pull and
test." The script ran as written — eleven images in five minutes, $1.55,
every painting delivered its five landmarks in story order with the
lair largest at the upper right (Rome's Colosseum road comes down from
the upper left instead of up from the lower left, and its medallions
follow the painting) — and every one was measured the same way: the
grid, a guessed row of ten medallions and three chests drawn on the
painting with `tools/mapgrid.py`, looked at, moved where a medallion sat
on a wall or a chest on the road (Duat 2's gate chest, the Aegean's
ruins path, the fjord's climb), looked at again. The rows are in
`ChapterMapArt.byChapter`, a comment naming each stage's landmark. So
that the owner sees all twelve before he pulls, the tour grew a step 28
`chapter_maps`: the CI job launches it once per chapter with
`-tour-chapter K` (`TourView.pinnedChapter`) and shoots a frame each,
twelve frames a–l, about two minutes more on the runner. Gemini since
the pause: the key art (0.14), the stones (2.95), Duat 1 (0.14), the
eleven (1.55) — $4.78 of the month's ten.

### The spoils panel: the genre's reward box (2026-09-14, late)

The owner, with Summoners War's "World Boss Reward" popup beside our
third victory frame: "You see how nice this looks? Why does ours look so
basic and ugly?" Read against his screenshot, theirs is: a framed box
(dark wood, a gold rim, corner studs) with a title ribbon standing on its
top edge and an X at the corner; a header row inside — the reward's own
icon and its rank ("SSS Treasure Box"); a 3×3 grid of tiles about 57
points square, each a dark rounded socket with a thin bevel, the item
PAINTED large in it (the crystal cluster, the rune, the chest) with a
glow behind a special one, and the count printed bold on the tile
itself — "+12,000" in white with a dark edge, no name; and one gold OK
bar under the grid. Epic Seven's stage result is the same anatomy with
the rarity on the tile's frame; Raid's chest opens into item cards with
rarity frames. Ours was a loose row of six 92-point cream tiles with a
grey system glyph and 9-point text on each, floating in the empty
middle of the screen after the 3D chest had lifted away, the count in
gold under the name. Four faults: glyphs where the genre has paintings;
no panel, no title, no header; counts too small and off the tile; tiles
small and washed out, cream on cream.

Options for the icons. (A) Restyle the glyphs — bigger, on darker
sockets, with a glow: free, and still a set of system symbols. (B) One
Gemini image per item, about forty items at 14 cents: about $5.60, past
the month's ten with $4.78 spent. (C) Paint them as SHEETS the way the
relic stones were repainted — nine icons to a 3×3 image on black, one
hand across the set, keyed off the ground by a flood fill from the cell's
border, trimmed and shipped at 256 px with alpha: five sheets, about
$0.70 plus a re-roll. (D) Meshy's text-to-image: the price per image is
unknown and the credit floor applies. C is the choice; the tool is
`tools/item_icons.py` (`--list`, `--paint <sheet>|all`, `--split`,
`--preview`), the keys are the game's own ids where it has them (an
essence's, a stone's) and one word where it does not (`drachma`,
`divinity`, `energy`, `unit_exp`, `player_exp`, `laurels`,
`rank_points`, `relic_cache`, `scroll_<type>`, `awakening_cache_<element>`),
forty-two icons in five sheets, and NOTHING IS PAINTED until the owner's
word for this batch.

What is built, with no art needed: `ItemArt` (Components.swift) maps a
key to `item_<key>.png`, a glyph and a tint; `ItemIcon` draws the
painting when it is in the bundle and the glyph in its tint until then;
`OutlinedText` prints a count with an edge (eight offset copies under the
fill — SwiftUI has no text stroke); `RewardTile` is the tile — the relic
grid's stone plate in a bronze bevel, the item at three quarters of the
socket, the count bold on the bottom-right corner, a graded thing's
colour on the inner rim and its stars under it, the name in small type
below, a relic as its own stone — with an `init(grant:)` for anything the
bazaar or the quests pay; and `SpoilsPanel` is the third act of a win:
the cream marble panel, 600 points wide, "SPOILS OF VICTORY" on a ribbon
standing on its top edge, the chest painting with the stage's name and
its three stars and the First-clear chip as the header, the spoils as
one row of up to six tiles or two rows of up to twelve popping in one by
one on the chest's beat, and the bronze Continue inside the panel. The
panel springs in where the chest stood the moment the flash takes it.
The same tile now draws a tribute's grants (52 pt, named), the bazaar's
offers (42 pt, the count only; the title above says what they are), and
the login gift's days (`ItemIcon` 16 pt); the stage popup's drop rows and
the wallet strip carry `ItemIcon` too, so the coin, the crystal and the
bolt land in the top bar the day they are painted. `BattleSummary.Loot`
carries the key. Tour frame 20-victory-c photographs the panel.

### The fight as the genre frames it (2026-09-15, morning)

The owner, with three screenshots — our Coils of Apep beside a Summoners
War wave and a Summoners War boss: "The health bars are not above the
heads. Also the UI of the skills and the descriptions like the bottom
left UI and more I just don't like. Plus it's hard to see the boss. 1.
Look at the graphics and backgrounds of summoners war. I want THAT level
of detail. 2. Look at the camera angles. Also most bosses and levels are
3 waves, 1 being a boss. Can we do that? 3. Look at the camera angle of
the boss battle."

**Read off his two frames (2000 px across for an 852-point screen, 2.35
px a point).** The wave: every unit wears its bars OVER ITS HEAD — a
level badge (a 20-point disc, the number in white, ringed) on the left
end of a 68 × 7 green health bar, the thin blue attack bar under it in
the same dark track, the status tiles (19 pt, red-framed, a turn count
in the corner) above the track and the matchup arrow (30 pt) above
those; the plates are the only readout on the field. At the bottom left
three 38-point squares: a gear, ×3, play. At the bottom right three
55-point skill squares in gold-orange painted frames, the one in hand
lit, nothing behind them. At the top of a wave, nothing but a chat
bubble. The camera is HIGH — the floor's carved pattern reads — and
turned so the two rows lie on a diagonal, the team across the lower
left third, the enemies across the upper right, figures about 22% of
the frame tall. The boss: a gold bar the full width of the very top
with the blue attack bar under it and the boss's own icons at the two
top corners; the boss's head at the frame's top edge and its fists at
the sides, filling the upper 60%; the team in a row at the bottom, seen
from behind and a little above, about a quarter of the frame tall, its
plates over its heads; the camera low, close, nearly level.

**Ours before this.** Bars UNDER the feet (2026-09-11); a 54-point actor
plate at the bottom left with the unit's name, YOUR TURN, its health
line and "Choose a skill · Tap a skill to read it; hold it for the full
card"; a column of three team readouts down the left; a damage feed down
the right; a turn gauge of portraits across the top with AUTO, ×1 and
the log beside it; the skills three 60-point cream tiles on a cream
plate; the boss bar a capsule of name, bar and numbers; the camera 26°
down from −15°, the enemies a flat row across the middle; the boss a
stride beyond the rim, sunk 42%, framed from 18 m at 20° down, 30% of
the frame tall and unlit in front of a night painting.

**Built (parts 1 and 2, one push).** `UnitPlate` over the head: one
track (66 × 14.5) holding the 6.5-pt health bar and the 3-pt attack bar,
the level badge (`PlateArt.levelBadge`, `Combatant.level` rides along)
overlapping its left end in the element's ring, the status tiles on
the track and the matchup arrow above them; `layoutPlates` projects the
top of the figure (`spec.height`) and stands the track 12 pt over it.
The HUD is the genre's: `bossBar` the full width at the very top (name
and numbers on a line, then a gold health bar over a blue attack bar in
one dark track, the barrier and the chips where they were), `topStrip`
small at the top left (the stage, the wave, a repeat run), `controls`
at the bottom left (gear → the log or forfeit, ×N, play/pause for auto),
`skillRow` at the bottom right — `SkillButton` a 60-point dark socket
lit from behind in the caster's element, the glyph white and large, the
name small, the estimate on the bottom edge, a gold frame that brightens
and grows in hand, a dark veil with the turns left while it cools. The
actor plate, the team column, the combat feed, the turn gauge and the
target strip are deleted, not hidden. The cameras: home −32° / 36°
(solved in the Python port before it was tried — a three-a-side's team
feet 75% down across the left third, the enemies' 45% down across the
right third, both a sixth of the frame tall, the far rim 23% down); boss
−8° / 8° with the feet at 0.94 and the head at 0.98, the boss ON the
rim (−8.4) and sunk 32% — 13 m out, 3.4 m up, the boss 46% of the frame
tall with its head a tenth down, the team 39% — and a warm spot light
riding with every boss, aimed at its chest, so it is the brightest
thing on the field. What the frames must show: the diagonal rows, the
plates over the heads with the level in the badge, the boss filling the
upper half, the corners as the genre has them.

**Not in this push.** Three waves per stage (part 3: `generatedChapter`
builds `laterWaves` the way the Labyrinth does, a wave boss on the
third, the sim mirrors it). The environment's detail (part 4) is the
one that costs: SW's floors are carved patterns with bevelled edges and
the whole set is one hue; ours is a flat repeated tile under a magenta
flood. The free half is a colour grade per environment and a bounded
arena; the rest is Gemini floor tiles (about ten at 14 cents) and Meshy
set pieces at 30 credits each against a balance of 2,133 over a floor
of 2,000 — four props, or the owner's word to go lower or buy more.

### Three waves a stage (2026-09-15, part 3)

The owner: "most bosses and levels are 3 waves, 1 being a boss. Can we
do that?" Summoners War's scenario stage is three waves — two of the
area's mobs, the third with its mid-boss, and the area's boss on the
last stage's third wave; the Labyrinth here already fought that way.
Every campaign stage does now. `generatedChapter` builds the first wave
as `min(3, 2 + i/4)` of the roster at ×0.75, the second the same count
two places on at ×0.85, and the third two adds at ×1.0 with the
chapter's boss at ×1.4 on the last stage or a LEADER of the roster — a
grade up, a step higher in level, ×1.3 — on every other; Duat 1's five
stages were rewritten by hand in the same shape. The team's wounds and
cooldowns carry from wave to wave (`BattleEngine`), the HUD counts
"Wave 1/3", the arrivals walk on from the far side, and the boss's line
is spoken when ITS wave walks on (`announceBoss(ifPresentIn:)`) rather
than at the opening of a fight it is not yet in. The third star's par
grows with the waves (`CampaignService.starRating`: the old 18 or 30
turns, times the waves, times 0.8 — 43 on a normal stage, 72 on a boss
stage).

Measured with `balance.py --campaign --chapters --tiers`, the sim
running the same three waves (`STAGES` as wave lists,
`generated_waves`): the ladder still steps where it did — Duat 1 opens
solo and needs a second unit at 1-2 (a solo cannot outlast three
waves; the tuning target moved from "solo at 60%" to "two units at
90%"), Duat 2's boss needs 5★s, Olympus 3's 5★s with relics (98% in
150 turns), Yggdrasil 3's maxed 6★s (137 turns), Rome and the Jade
Court 6★s (Jade 1's boss 204 turns for the 6★s, 105 for the gods), and
Hard's top boss now wants the gods where a single wave took the 6★s
(Jötunheim Hard: 6★s 0%, gods 100% in 134 turns; Hell everywhere is
the gods'). The turn counts are the sum of three fights, so a three-wave
median of 150 is a 50-turn wave. The multipliers were not retuned: the
curve held its order.

### The set dressed: the free half of part 4 (2026-09-15)

The owner's first point, with Summoners War's frames beside ours: "Look
at the graphics and backgrounds of summoners war. I want THAT level of
detail." What the genre's stage has, frame by frame: a floor of CARVED
tiles whose edges catch the light, one strong hue over the whole set
(Faimon red, Mt. Siz blue-white, Kabir ochre), a bounded arena — an
edge on every side, a circular design under the fight — a few big set
pieces at the edges, and air that moves: leaves, embers, snow, motes.
What ours had: a painted tile repeated fourteen times each way with its
shading baked flat, a fixed blue fill over every set whatever the
painting's colour, a far parapet and two open sides, no floor design,
dust motes only.

**Three ways to get the carved floor.** (1) Gemini paints each realm's
floor again with a carved arena pattern and bevelled tiles, and a
matching normal map is derived here: about ten images at 14 cents, the
best result, and Gemini is paused. (2) Meshy makes the arena as one
mesh: 30–300 credits, unrepeatable across realms, and the balance is
2,133 over a 2,000 floor. (3) Derive the relief from the paintings we
already have: a height field from each tile's luminance (grout dark and
low, stone bright and high, cracks low), a normal map from its gradient,
SceneKit shades it — free, and on the lit preview the grout bevels and
the cracks cut in exactly as the genre's do. (3) is built, and (1) is
the upgrade the owner can buy on top of it (the maps derive the same
way from any new tile).

**Built, all of it free.** `tools/floor_relief.py` writes `<tile>_n.png`
for the four floors and two rocks (512 px, ~2 MB in all, PNG because a
JPEG's ringing is a surface full of dents), and `floorMaterial` /
`rockMaterial` wear it at the diffuse's own repeat with roughness per
stone (marble 0.52, slate 0.66, sandstone 0.84, moss 0.95). The slab's
tint became `mottle`: the tint with nine soft clouds of shade through
it, drawn wrapped so it tiles, at 1.6 repeats across 44 m. The arena's
sides are walled (`sideWalls`: a 0.9 m balustrade with a coping and a
post every four metres at x ±9.8, outside the side pieces at 8.5 and a
five-a-side's outer marks at ±5.4; projected in the Python port of the
solve before it was built — the far-side wall runs from (0.39, 0.07) to
(0.08, 0.43) of the home frame, the near-side one lies along the right
edge and enters the frame only for a five-a-side, and both flank the
boss in the boss frame). The floor is inlaid (`arenaInlay`: a 6.6 m
quad a finger above the slab with an outer band, thirty-six ticks, two
rings, an inner ring just inside the rows and an eight-point star,
MULTIPLIED over the tiles so the grooves darken the stone like a cut
and the relief shows through them; geometry only, since a device drawn
in code is what the owner called clip art). The set and the painting
are lit as ONE place: `PaintingPalette` reads each painting's sky (top
eighth), horizon (37–56% down) and ground (bottom fifth) off a 32 × 32
reduction — measured here first: the Duat's horizon is #512E15, the
marsh's #2B463D, the fjord's #536E7C, the Serpent Deep's #08080D — and
the fog and the sky beyond the painting, the fill light (the sky, half
way to white; it was a fixed #7F9BD8 blue over every set) and the
ambient (the horizon, mixed 35% with the hand-picked `fogHex` so the
Serpent Deep keeps its violet over its measured near-black) take theirs
from it. The camera wears one grade per place (`grade(for:)`: warm
stone at saturation 1.06 / contrast 1.06, the deeps at 1.05 / 1.12 with
a darker vignette, the cold realms at 1.0 / 1.08 with the fjord lifted
+0.08, Rome by night at 0.96 / 1.10).

**The first run of frames, and what it changed.** Every set came out in
its own hue with the relief, the inlay and the walls reading at 1:1 —
and the FIGURES in that hue too: Zeus green in the marsh, blue in
Jötunheim, orange in the Duat, because the hand-picked key light
already carried the realm's colour and the fill and the ambient now
carried it again. The genre keeps its monsters their own colours inside
a tinted world, so the key is lifted 45% toward white, the ambient and
the fill a little further, and the warm sets' saturation came down from
1.12–1.15 to 1.06–1.08 (the braziers' orange on a mottled sandstone
floor had made the Duat a sheet of orange). One arena frame was a wall
of yellow: an ultimate's white flash caught mid-frame, normal eight
seconds later. And each realm has weather (`weather(for:)` →
`VFXLibrary.weather`, on the sprites the effects already ship): embers
rise in Egypt and the arenas, leaves fall in the marsh and under
Yggdrasil, reed chaff over the Field of Reeds, snow in the fjord and
Jötunheim, petals in the Peach Garden, wisps in the Serpent Deep, the
Necropolis, the Hydra's lair and at the Dragon Gate, motes on Olympus,
the cliffs and in the Forum. Every count is low: weather is felt at the
edge of the eye.

**Seen before it is handed over.** Tour step 29 (`realm_battle`) fights
the first stage of a realm named at launch (`-tour-environment`), the
engine built directly because the stage is locked on a fresh save, and
the CI job relaunches it six times — Olympus, the marsh, the fjord,
Jötunheim, Rome, the Peach Garden — so the sets the other three battle
steps never reach (all Egypt) are photographed too.

**The half that costs, for the owner's word.** Gemini: one carved floor
tile per realm family — sandstone with a sun-disc arena, marble with a
meander border, slate with a knotwork ring, moss stone with a root
circle, a Roman mosaic, a jade-court flagstone — ten images, about
$1.40, $4.78 of the $10 spent so far this month; the relief derives from
them the same way. Meshy: the set pieces the recipes stand in for
(`prop_stone_lion`, `prop_pagoda_lantern`) and the dungeon set (task
#43) at 30 credits each — four props would end at 2,013 over the 2,000
floor, so the rest waits on a lower floor or more credits.

## Real animated attacks: the five-god test (2026-09-15, night)

The owner: "I want REAL animated attacks (that includes effects, not
just the animated model)", with a floor of 1,500 for the test — 633
credits over the 2,133 in hand.

### What a Summoners War attack is made of

Frame by frame, one of the genre's attacks is five things at once, and
ours had two of them: (1) a motion that belongs to THIS monster — a
lioness pounces, a thunder god hurls, a scribe writes in the air;
(2) a painted effect that belongs to THIS skill, big and bold, drawn as
a frame sequence, not a particle puff; (3) the hit landing on the exact
frame the blow connects, with a freeze, a shake and a flash; (4) a
camera that pushes in; (5) a sound. We had (3), (4) and (5) — the
freeze, the shake, the push-in, the hit sounds — and for (1) every one
of 103 characters swung one of four stock clips (a sword slash, a
hammer, a spell cast, a bow), and for (2) each element had a puff of
two painted sprites. That is why the fights read as canned.

### The motion: three ways, and the one taken

- Meshy Text to Motion, a sentence per skill, applied to the family's
  rig: 13 credits a clip in prime mode (10 + 3 to apply), Zeus's
  ultimate took two takes (26), nothing else changes — the game already
  plays `<asset>_<clip>.usdz` per skill slot (basic → skill 1, heavy →
  skill 2 and every ritual, ultimate → skill 3). CHOSEN.
- Better stock picks: 3 credits a clip, but the library has no spear,
  claw, staff, dagger or whip, so most families cannot be fixed with it.
- Mixamo mocap retargeted in Blender: no credits, days of pipeline,
  generic again. A freelance animator: $150–400 a clip, $45k–120k the
  roster — the genre's own cost, not this game's.

Five families, three clips each (Zeus keeps his ultimate): Anubis,
Sekhmet, Zeus, Ares, Thoth — the three flagship remakes and two other
kits (a shield-and-sword warrior, a caster), so the test shows a
pounce, a throw, a shield bash and a spell as well as a slash. The
sentences are in `scratchpad/motion_wave.sh` and the manifests; each
describes the motion in human terms, in place, starting and ending in
the fighting stance so it cross-fades with the idle. Durations 2.0 s
(basic), 2.5 s (heavy), 3.0 s (ultimate): the engine retimes each
one-shot to its contract (1.3 / 1.7 / 2.4 s) inside 0.6–2×. Fourteen
clips, 182 credits at one take; the motions all came back in about
twenty seconds each, the application in a minute or two.

### The effects: what can be painted, and with what

Veo flipbooks (the fireball) are the right tool and are barred: Veo
bills through the Gemini key and the owner's Gemini cap is $10 a month
with $4.78 spent. Gemini's image model is paused for the same cap. But
Meshy's text-to-image (`meshy.py picture`) paints with the same Google
model (nano-banana-2) in MESHY credits — 6 a picture, measured on the
first one (an accidental one: a probe with `dry_run` in the body was
accepted and painted the prompt "x"; noted, 6 credits) — inside the
floor the owner just set. So each skill family's effect is a painted
4 × 4 flipbook sheet (16 frames on black, keyed and shipped by
`vfx_ship.py`, played by `VFXLibrary.flipbook`) plus the code-built
parts that already work: the slash arc, the bolt column, the storm
ring, the sky flash, sparks, the freeze and the shake. The sheets to
paint, one per skill family: a lightning strike (Zeus), a claw rake and
a solar burst (Sekhmet), a shadow-and-gold burst (Anubis), a blood
slash (Ares), a golden script burst and a heal (Thoth), a ground
shockwave for every heavy slam. About 8 sheets plus re-rolls, 60–90
credits. The risk, and the reason the first sheet is judged before the
rest: a painter's 16 frames may not read as one motion; a sheet that
flickers is played slower with a cross-fade, or cut to its four best
frames.

### Timing

A bespoke clip's blow lands where the animator put it, not at the
stock clip's 42% / 55% / 62%: each shipped clip is looked at frame by
frame (`preview.py --frame`) and its contact fraction written into
`BattleSceneController.contactFraction`'s per-family table, so the
freeze, the flash and the damage number land on the frame the claw
closes. Zeus becomes ranged (`melee: false`): a thrower does not run
up to its victim, and the bolt sprite flies from his hand on the frame
of release.

### What the frames must show

The tour's team is Anubis, Sekhmet and Zeus, so steps 6, 8, 18 and 29
photograph the new clips and effects mid-swing; a preview sheet per
clip (seven frames) is sent with the report, and the owner judges the
motion on the phone.

**Shipped (the same night).** Fourteen clips, every one right at the
first take (the sheets of seven frames are in the scratchpad: Anubis
lunges, leaps to a one-knee slam and weighs the scales; Sekhmet slashes,
pounces twice and roars into a spin; Zeus hurls and drives the bolt
down; Ares bashes and thrusts, charges into a chop and whirls; Thoth
writes in the air, opens the scroll and reads the decree), 182 credits.
Eight painted sheets at 6 each plus one re-roll (the blood slash came
back on grey cells; "the entire image background is solid pure black"
in the prompt fixed it) and one accidental 6: 242 credits in all,
2,133 → 1,891, floor 1,500 untouched by 391. `tools/vfx_sheets.py`
ships the sheets with alpha and a fade over each cell's outer ring — a
painter's brightest frame fills its cell to the corners, and a square
of light bursting on a victim was the one thing a sheet could do wrong.
The contact frames read off the clips: Anubis 0.38 / 0.50 / 0.55,
Sekhmet 0.45 / 0.42 / 0.45, Zeus 0.47 / 0.40 (ultimate 0.68), Ares
0.47 / 0.50 / 0.45, Thoth 0.55 / 0.60 / 0.65.

**The crash, twice, and the rule it left (2026-09-15, later).** The
commit's CI run was green and its frames showed every fight but one: the
arena's three frames were the iPhone's home screen. The console said as
much as it could — the last line was Chang'e's ultimate clip loading, and
two seconds on six SceneKit assertions across three render threads,
`C3DRendererElementIsHidden(rendererElement) != true … Hidden nodes should
have been removed from the pipeline already`, then nothing. The first
diagnosis blamed the one texture the commit swapped inside an
`SCNAction.customAction` block (the shockwave ring's frames, on the render
thread) and moved it to a main-thread timer; that run's arena played eight
casts clean — and the job's NEW crash capture (`crash-*.txt`, the host's
report for the app, copied into the frames branch; `ciframes.py` prints
the crashed thread) caught the dungeon battle dying instead, 3.5 s after
Zeus's Keraunos with the main thread idle in its run loop: `SIGSEGV` in
`SCNNodeRemoveDeadParticleInstance → +[SCNNode nodeWithNodeRef:] →
objc_loadWeakRetained` on the render queue. SceneKit's particle manager
keeps a finished one-shot system's instance and looks its node up when it
dies; the one node the commit removed while a one-shot system of its was
still alive was the ultimate's charge host — motes born through 80% of a
1.63 s wind-up with lives of up to 130% of it (the last dies at 3.4 s),
the host gone at the wind-up + 1.5 s (3.1 s), the crash at 3.5 s. Both
deaths are that one mistake: removed in an action, the pipeline asserted
on the hidden instance; removed on the main thread, the manager
dereferenced the freed node; and three ultimates in the same run's arena
lived because the window is a few tenths wide and a life is rolled. The
motes now die by the blow and the host waits 1.5 wind-ups + 1 s. The rule: **a node with a one-shot
particle system goes only after the system has finished** (every `spawn`
host waits 3 s over sub-second bursts, which is why they never crashed);
and, hygiene rather than cause, nothing swaps a texture or touches the
scene graph from inside an action's block. Every cast prints a stamped
`[Perf] cast …` line now, so a console that ends mid-fight names the cast
it ended in, and the system log covers the whole tour rather than its
last twelve minutes.

## The light tamed and the skill squares repainted (2026-09-15, night)

The owner, with four battle frames in front of him: "Lighting and contrast
feels too bright doesnt it?" And, with a close-up of the three skill
squares: "Also cann we get better skill artwork? AND I hate having the
NUMBER show on top of the skill. We dont need that. Lets do it like
summoners war and only show the damage when the character attacks."

### How bright is too bright, in numbers

`python3 tools/framelight.py` reads every battle frame off the CI branch
and prints, per frame and per band (the painting's band, the middle where
the enemies stand, the near floor), the mean luminance and the share of
pixels at 240 or over — pixels with no detail left in them. The run before
this pass:

| frame | painting | middle | near floor |
|---|---|---|---|
| Duat (6-battle-a) | 68 / 0.2% | 88 / 0.5% | 87 / 0.0% |
| arena (8-b) | 65 / 0.2% | 89 / 0.5% | 97 / 0.1% |
| Olympus (29-a) | 131 / 2.6% | 173 / 17.5% | **178 / 25.2%** |
| the fjord (29-c) | 108 / **16.5%** | 162 / 29.4% | 84 / 1.6% |
| the Vault (18-c) | 95 / 3.1% | 107 / 8.8% | 79 / 4.6% |

So it is not a global overexposure — Egypt and the arena are right, and
a quarter of Olympus's floor is a sheet of white with no stone in it. The
sets that blow are the PALE ones: white marble, ice, sunlit sandstone.
Anything that lifts or lowers everything equally would fix Olympus by
ruining the Duat.

### The options

1. **Turn the lights down globally.** One number, and it takes the Egypt
   sets — which the owner has never complained about — down with it.
   Rejected.
2. **Tone-map the camera (`SCNCamera.whitePoint`).** With `wantsHDR` on,
   SceneKit maps luminance through a curve whose shoulder sits at
   `whitePoint`, and ours has been at the default 1.0 for the life of the
   project: everything at or above 1.0 clips flat to white. At 1.85 the
   curve keeps rolling past 1.0, so a lit marble floor keeps its grain and
   only a real emissive reaches paper white. This is the shoulder every
   film-grade renderer has and the reason the genre's sunlit sets still
   read as stone.
3. **Expose each set from its own painting.** `PaintingPalette` already
   reduces the backdrop to 32 × 32 to colour the fog and the fill; the
   same reduction gives its mean luminance, and a set whose painting is
   pale is a set whose lights are about to double it. `exposureOffset`
   now carries the grade's hand-picked number MINUS up to 0.55 stops for
   a bright painting (nothing for a painting at or below mid grey). The
   set is lit to match its painting rather than on top of it.
4. **Trim the lights.** key 1,400 → 1,150, fill 500 → 400, ambient
   300 → 240, the image-based light 1.6 → 1.15: about a fifth off, which
   is the headroom the shoulder needs to work in.
5. **Bloom off the floor.** 0.3 over 0.94 was tuned when nothing rolled
   off; a clipped floor above the threshold is what SPREADS the white
   over the figures. 0.22 over 0.975.
6. **Polished stone is a mirror.** The marble floors went to roughness
   0.52 in the dressing pass and threw the key back as one sheet; 0.62,
   with the relief map doing the reading instead.

Taken: 2 + 3 + 4 + 5 + 6. The target is every band under 2% clipped with
its mean between 70 and 130, measured by `framelight.py` on the frames of
the run that follows — a number, not an opinion.

### The skill squares

Summoners War's skill buttons carry ONE thing: a painted icon, in a
metal frame, greyed with a number over it while it cools. No name, no
damage. The damage is the floating number over the victim when the blow
lands, which this game has had since the first build. Ours carried a
painted-on estimate ("≈847"), the skill's name at 8 pt, a target glyph
and the icon, all inside 60 points — four things where the genre has
one, and the estimate was the one the owner named.

So the estimate is gone from the square (it stays on the held card,
where a player who wants it is asking for it), the name is gone, the
target badge is drawn only when a skill is NOT a plain single-target one
(so the common case is art), and the icon fills the square.

**The artwork.** A painted icon per skill is impossible here: seventy-nine
families × three skills × five elements is thousands of images. The
genre's own answer is an icon per skill drawn once by an artist; ours is
an icon per **what the skill does** — twenty-seven of them, painted, with
the caster's element as the light behind. A skill resolves to one by:
its named effect first (`VFXLibrary`'s own names — a keraunos is a bolt,
a lioness's rake is three claws), then what it actually does in the
engine (revive, heal, cleanse, strip, shield, a buff, an attack-bar drag,
a stun, a defence break, a burn, a drain, a curse), then its shape (all
enemies, three hits, a heavy single blow, a plain strike), and last its
element's own impact. `SkillArt` in `Components.swift` holds the table;
`tools/skill_icons.py` paints the three 3 × 3 sheets through
`meshy.py picture` (6 credits a sheet while Gemini is paused), keys them
off the black ground and ships them as `skill_<key>.png` at 256 px. A
missing painting falls back to the same table's SF Symbol, so the button
is right before the art lands and better after.

**Painted (the same night), 24 credits.** Sheets 1 and 2 were right at
the first take — a scimitar through its own arc, an axe's crescent, a
spear through a cracked shield, arrows, claws, a hammer on flagstones, a
force ring, a column of light, a starburst; then flame, ice, wind curls,
a wave, a forked bolt, an eye in smoke, a burning tablet, a chained
bomb, a red crescent drawing threads. Sheet 3 came back with a GOLD
FRAME drawn round every icon and a brown ground inside it, which keys
wrong and matches neither of the others, so the prompt learned to refuse
frames, panels, tiles, plaques, ground and scenery by name and the
re-roll (6 credits) put the nine shapers on the same black: a chalice, a
burning feather over an open palm, a bronze aspis, a bell, a fist
tearing a veil of light, a winged laurel, a sinking one, a cracked star
in its rings, an hourglass in a curl of wind. Keyed off the background
by a FLOOD FILL from each cell's border rather than by brightness, so a
dark line inside an icon survives where the flipbooks' brightest-channel
alpha would have eaten it. 1,891 → 1,867; the owner's floor for these
tests is 1,500.

**Measured after (the same run).** `framelight.py` on the frames of
ee4e549, against the table above: Olympus's near floor 178 / 25.2% → 148
/ 0.0%, its middle 173 / 17.5% → 142 / 0.1%; the fjord's painting band
108 / 16.5% → 52 / 0.2%; the Vault 95-107 / 3-9% → 90-102 / 0.1-0.3%;
and the sets that were already right barely moved — the Duat 68/88/87 →
63/83/86, the arena 65/89/97 → 62/83/90. Nothing in any battle frame is
clipped above 0.7% now except two frames that are an ultimate's white
FLASH, which is an effect and not the light. The pale sets came down a
sixth and the rest a twentieth, which is what a shoulder plus a
painting-matched exposure is supposed to do.

**And the squares must differ inside one kit.** The first frames showed
Zeus with three IDENTICAL squares: his bolt, his clap and his keraunos
all name a bolt in `VFXLibrary`, and the table handed all three the same
icon — worse than no art. `SkillArt.candidates(for:)` now returns every
icon a skill could wear, best first, and `SkillArt.keys(for kit:)`
walks a unit's skills taking the best each has that an earlier one has
not taken; the battle row and the unit sheet both resolve through it.
Zeus reads bolt, ring, column — read off the unit sheet in the frames of
e3e312b, where Thunderclap wears the force ring and Keraunos the column
of light.

**And a painted-on-black icon needs a dark ground.** On the unit sheet's
CREAM panel the force ring's hollow centre read as a blot: the icons are
keyed off black, so their dark parts are transparent and take whatever is
behind them. `SkillIcon(socket: true)` puts the battle square's own stone
plate and gold edge behind the art wherever it stands on cream — the unit
sheet's tiles and the battle's held card. The battle squares draw their
own socket and leave it off.

### The white sheet was a lamp, not the light (2026-09-15, later)

The owner sent back the one frame of the shoulder pass that still reads as
a white-out: a fight in the Duat with a white blob over the enemy row and
the floor bleached for four metres around it. "This one still needs a
fix." `framelight.py` had flagged it too — 10.7% of that frame's middle
band with no detail in it while every other band in the run sat under
0.4% — and the first report called it "an effect, not the light", which
was half true and not good enough.

Read off the console's cast stamps, the frame is 3.4 s after
`Thunderbolt by zeus as attackBasic`: a BASIC ATTACK, cast every four
seconds. What it fires is five things at once, and one of them is the
whole problem.

**`VFXLibrary.flash` is an omni light at intensity 4,000 whose
`attenuationEndDistance` is FOUR TIMES its radius.** The battle's key
light is 1,150. So every impact in the game — all twenty-four call sites,
every basic attack included — drops a lamp three and a half times the sun
into the set, reaching 9 m for a thunderbolt and, through `skyFlash`
(radius 7 × scale), **28 m**: further than the 44 m slab is wide. It does
not light the victim; it relights the arena. The shoulder added on
2026-09-15 stops a bright surface clipping, and it cannot help a surface
that is genuinely being lit to four times white.

**What the genre does.** Summoners War's hits are bright but its scene's
exposure never moves: the brightness is in ADDITIVE SPRITES, which only
touch their own pixels, and in a brief full-screen flash for an ultimate.
The 3D set is not relit. A point light in an impact is for picking the
victim and the metre around it out of the dark — a local pop against the
key, not a second sun.

**The fix, in one place.** `flash` becomes local: its reach is
`radius × 1.5` instead of `radius × 4` (so a thunderbolt's flash is dark
before it crosses the 6 m to the player's row), it starts falling off at
a third of the radius, and its intensity scales with the radius from
1,320 to a cap of 2,400 instead of a flat 4,000 — the key light's
neighbourhood rather than several times it. Every one of the
twenty-four impacts improves at once, which is the point of fixing the
helper and not the call sites.

Three smaller things with it. `skyFlash` — the flash that makes lightning
read as lightning — is a wide weak lift now (intensity 600, its own
falloff) and is spent only on a HEAVY or an ULTIMATE; a basic attack no
longer flashes the sky. The lightning flipbook is tinted to 60% white
rather than pure white, so an additive sheet stops climbing past the
bloom threshold on its own. And the basic's numbers come down to a
basic's size: the sheet 3.6 m → 2.6, the bolt 9 m → 7, the sparks 90 →
55, its flash 2.2 → 1.5. The rule this leaves: **an effect may not
relight the set.** Brightness belongs to the sprite, which covers only
itself; a light in an effect reaches about as far as the thing it is
lighting.

**And the same mistake one screen further on.** The run that proved the
impact fix (the worst 64 × 64 patch fell from 100% blown to 25%, no band
over 1.6%) photographed the Labyrinth's third wave as a pale wash with
only the health bars legible — 191/211/207 mean and almost nothing
clipped, which is what a scene lit to several times white looks like
AFTER the shoulder: it rolls off instead of clipping, and it is still a
white-out. The boss's own lamp: `intensity = 3,000` through a **75°
cone** with `attenuationEndDistance = 34`. The key light is 1,150 and the
slab is 44 m across, so a boss walking on lit the entire set two and a
half times over. It was added on the owner's "it's hard to see the boss"
and it made everything else hard to see instead. The lamp stands about
8.5 m from the chest it aims at, so: 2,400 through a 46° cone, gone by
14 m — the boss picked out of its background, and nothing else touched.
Both lamps are the same lesson, and `framelight.py`'s worst-patch column
plus the band means are what will catch the third one.

## The tutorial, and a guide called Athena (2026-09-15, planned)

The owner: "The next thing im going to want to work on is a full tutorial
of the entire game. Like how summoners war uses Ellia, maybe we should
have a 2D Athena that runs you through the tutorial. Can you research
summoners war tutorial and come back to me with a plan?" Plan only — no
code until he picks.

### What Summoners War actually does

Read off the beginner guides and the wiki summaries (the fandom wiki and
several guide sites are refused by this environment's egress proxy; the
search summaries and the sources below are what the research rests on).

- **One named guide, and she is also a unit you own.** Ellia — a Water
  Magic Knight — meets the player at the start, teaches the basics and
  hands out the main quests. She is not a disembodied tooltip: she is a
  monster in the collection, which is why players remember her.
- **The hard tutorial is short and is all DOING.** A first battle, then a
  first summon that Ellia runs for you, then straight into the early
  areas. The player is never sat down and lectured.
- **Systems arrive where they become useful, not at the start.** The
  first area (Forest of Garen) teaches fighting; runes are not taught
  until the THIRD area (Mt. Siz), because that is where the first rune
  drops. Kabir Ruins follows.
- **The tutorial pays.** Five standard monsters over the opening, good
  enough to carry the early game, plus scrolls at each step.
- **The long tutorial is a CHECKLIST, not a script.** "Summoner's Way" is
  a tiered list of one-time quests — Novice, Intermediate, Advanced —
  each teaching one system, each with its own reward, each tier unlocking
  the next and paying a large prize at the end (750 crystals for the
  full set). Later tiers cover the Dragon's Lair, the Necropolis, the
  Rift dungeons, Raids.
- **Experimenting is free for a month.** New players get free rune
  removal, so a beginner cannot brick a monster by equipping wrong.

And the FTUE literature agrees with all of it: get the player playing
inside thirty seconds, never pause the game to explain, point at ONE
control at a time, make the first actions pay, and make the player feel
clever rather than taught.

### What this game already has

`FirstHourStep` (IslandView.swift) is four coach-marks on the island —
summon, fight, equip, power up — each a caret on a landmark with one
line under it, a skip chip, and, importantly, `isDone(for:)` derived from
what the SAVE actually contains rather than a flag written by the screen
that did it. `QuestService` already has daily missions, sixteen feats
plus one per chapter, and a login gift: the skeleton of a Summoner's Way
is there. That is the foundation; none of it is thrown away.

### The plan, in five phases

**Phase 1 — the teacher.** One overlay that can appear on any screen: a
2D Athena bust at the left, a cream plate with her name and typewriter
text, a tap to advance, and a caret that can point at any control. Plus
a script format (a list of beats, each: what she says, what to point at,
what the player must do to advance) and the save fields (all Optional:
the step reached, the set of pop-ins already seen, the Way's claims).
This is the machinery every later phase uses.

**Phase 2 — the opening eight minutes**, the hard tutorial, one scripted
run:
1. Athena speaks over the island. The gods sleep; you will wake them.
2. A first battle she walks you into — tap an enemy, the skill squares,
   the element arrow. It cannot be lost.
3. The reward box, named.
4. The Summoning Circle: she runs the first summon, the reveal plays,
   the god is yours.
5. A second fight with the new god, which teaches waves.
6. The relic that drops: Collection, the unit, the slot, Equip.
7. The Hall of Ka: feed the spares, watch the level go up.
8. She hands the player to the map.

**Phase 3 — a pop-in per system, where it first becomes reachable.** One
Athena beat, one pointer, one reward, seen once (about fourteen):
relic power-up and its odds, evolution, awakening, the Labyrinth, the
Halls of Essence, the arena, Hard and Hell, the tribute chests, fusion,
the Tower, raids, the scroll types, the bazaar, auto-repeat and speed.

**Phase 4 — Athena's Way**, the checklist that replaces the feats screen
as the spine of the first week: three tiers (Initiate, Adept,
Hierophant), a dozen entries each, one-time, each paying, each tier
unlocking the next and ending in a large prize. Built on `QuestService`,
which already records every mutation that would tick one.

**Phase 5 — the art.** Athena as a painted 2D bust with four to six
expressions (neutral, pleased, concerned, urging, proud, surprised),
keyed off black the way the skill icons were.

### What it costs, and what has to be decided

Art: six expressions is 36 Meshy credits (6 each, the rate the skill
sheets measured) or about 84 cents of Gemini, which is paused and needs
his word for the batch. If Athena is also to be a PLAYABLE unit the way
Ellia is — the thing that makes a guide memorable — she needs the five
element cards and a rigged mesh on top: about 53 credits plus a card
batch.

Four decisions are his, and the build changes with each:
1. Is Athena a unit the player owns, or only a voice?
2. Can the first battle be lost, or is it floored the way the genre
   floors it?
3. Is the opening skippable, and is it replayable from More afterwards?
4. How much of the art to buy now, given Gemini is paused and the Meshy
   floor is 1,500 with 1,867 in hand.

Sources: the Summoners War wiki's Ellia and Challenges pages, Theria
Games' and sw-database's beginner guides, BlueStacks' Summoner's Way
write-up, and Udonis' and Game Developer's FTUE guidance.

### The owner's answers, and the plan as it now stands (2026-09-15, later)

1. **Athena is a voice, not a unit.** "Athena should be just a voice.
   Ellia can't battle." So no cards and no mesh for her: portrait art
   only, and she never appears in the collection or on a team.
2. **The first battle cannot be lost.** As the genre does it.
3. **Skippable AND replayable — and expand it.** "That would be a good
   idea, let's expand on that." See *The Lessons* below: this stops being
   a tutorial that is spent once and becomes the game's permanent help.
4. **100 Meshy credits** for the art. At 6 a picture that is sixteen
   images: eight expressions with room for re-rolls, and a sign or two
   for the shop below. Balance 1,867, floor 1,500.

**The name.** "Athena's Way" is out. Four candidates, and note that
Summoners War already uses *Blessing* for its beginner perk (Goddess
Amaria's Blessing, a month of free rune removal), so taking that word for
the checklist is the one option that lands closest to theirs:

- **Athena's Counsel** — she is the goddess of counsel, and a counsel is
  advice, which is exactly what the list is. Recommended.
- **The Aegis** — her shield; short, ownable, and it reads as protection
  rather than instruction.
- **The Owl's Path** — her bird; softer, more like a road.
- **Athena's Blessing** — the owner's own, clear, but see above.

The recommendation is **Athena's Counsel** for the checklist, and to keep
**Athena's Blessing** for a separate beginner GRACE if one is ever added
(this game already gives free relic removal, so a Blessing here would be
something else: a daily scroll for a month, say).

**The Lessons (the expansion of decision 3).** Every beat Athena gives is
a LESSON with an id, and every lesson is kept: a *Lessons* screen (from
More, and from the Obelisk on the island) lists them all — the ones she
has given, replayable at any time, and the ones still locked, named but
greyed, so a player can see what the game still holds. That turns the
tutorial into the manual, which almost nothing in the genre does.

Two consequences for the design:

- A lesson needs two modes. **Live**: she speaks on the real screen, a
  caret points at the real control, and the player must do the thing to
  advance. **Replay**: the same words on a card with a still of the
  screen it talks about and a "Take me there" button, because a player
  replaying the relic lesson may be standing on the island. The script
  format carries both from one definition.
- A replay never pays again. The reward is on the first completion only,
  recorded in the save.

**The opening is skippable once**, with the ask worded so the player
knows nothing is lost: "Skip the opening? Athena keeps every lesson in
More → Lessons." And "Replay the opening" is the first entry in that
list.

## A magic shop (2026-09-15, planned)

The owner: "we should have a 'magic shop' too right?" He is right, and
the genre's own Magic Shop is one of its load-bearing systems.

**What Summoners War's Magic Shop is.** A building that sells monsters,
summon scrolls and runes from a stock that ROLLS: four sell slots at
first, unlockable to twelve with mana stones or crystals. The stock
refreshes on a timer, and a player may pay crystals to refresh it early.
That paid refresh is the engine of the whole thing — players grind mana
and then refresh over and over hunting a Mystical Scroll, at roughly
130k mana a scroll and, over a hundred-refresh streak, about 20–30
crystals a scroll, which is cheaper than buying them. There are sibling
shops on the same pattern: the Guild Magic Shop (monster pieces, scrolls,
runes, grindstones, enchanted gems) and the Ancient Magic Shop (legendary
scroll pieces, 6★ legend runes, reappraisal stones).

**Why this game needs it.** Drachma has exactly ONE sink today — relic
power-up — and a currency with one sink stops meaning anything once a
player has what they want. A rolling stall is the sink, and it is also
the reason to open the game between energy ticks: a stock that changes is
a reason to look.

**The shape it should take here.** `ShopService` already has everything
but the roll: `Grant` covers scrolls, energy, drachma, divinity, a relic
by grade, essences, stones and bundles, and `Section` is already a row of
stalls (Daily, Testing, Scrolls, Energy, Relics, Essences). So the magic
shop is a new section whose offers are ROLLED and SAVED rather than
written down:

- **Six slots**, rising to ten as the summoner levels (no purchase — this
  game does not sell convenience for real money).
- **Free refresh on a timer**, on the same hourly tick the energy already
  runs on, plus a paid refresh in divinity that costs more each time
  within a day and resets with the day.
- **The stock**: a relic of a random set, slot, grade and quality; a
  scroll of a random type; essences; a whetstone or gem; a bundle of
  drachma-for-EXP; and, rarely, a UNIT — which is the row that makes a
  player look, exactly as the genre's monster row does.
- **Priced in drachma** for most rows, divinity for the rare ones, and
  every price rolled against the player's level so the shop scales.
- **Sold out is shown**, not hidden: a bought slot stays on the shelf
  crossed out until the refresh, so the player can see what the roll gave.
- Named for the world — the **Oracle's Stall**, or the **Night Market** —
  rather than "magic shop", which is Summoners War's own words.

**What it needs before it is built**: `balance.py --shop` pricing every
row against what a stage pays, so a refresh loop cannot out-earn the
campaign; the rolled stock in the save as an Optional field with its
roll seed and expiry; and the art, which is the item icons already
planned (task #79) plus a stall sign.

This is a SEPARATE piece of work from the tutorial and should not be
built inside it. Athena gets one lesson pointing at it, like every other
system.


### Built: the guide, the opening and the library (2026-09-16)

Both names settled — **Athena's Counsel** for the lessons and the **Night
Market** for the shop — and the first three of the five phases are in.

**The art, 6 credits.** `tools/athena_art.py` paints FOUR expressions in
ONE image as a 2 x 2 grid: calm, pleased, concerned, urging. One image and
not four, because `meshy.py picture` takes a prompt and nothing else —
there is no reference image on that endpoint, so two generations are two
different women. A 1024 sheet gives 512-pixel cells, which is what a
168-point bust wants on a 3x phone; a 3 x 3 would have given 341 and a
softer face. Right at the first take: the same face, helmet, owl and
chiton in all four, keyed off the black by a flood fill from each cell's
border. Balance 1,867 → 1,861 against his 100-credit allowance.

**The teacher.** `Lessons.swift` holds the data — a `Lesson` is an id, a
title, a topic, its beats, the anchor its caret sits on, the one line
under that caret, a `goal` read off the SAVE and an `unlock`. Two kinds,
and `goal` is the difference: a STEP of the opening keeps its caret up
until the save says the thing is done; a POP-IN has no goal and is over
when it has been read. Eleven written: six of the opening and five
system lessons, plus the Night Market's, which is deliberately locked
(`unlock: { _ in false }`) so the library shows a player what the game
still holds.

**The caret is a preference, not a table of coordinates.** This is the
part that had to be got right. `FirstHourStep`'s pointer was computed
from the island painting's own landmark anchors, which works exactly
once — on the island. A guide that must point at a tab, a button inside
a sheet and a slot on the unit sheet cannot know where any of them are,
so every control that can be pointed at now says where it is —
`.guideAnchor("island_gate")` — and `GuideOverlay` reads the rect back
out of a `PreferenceKey`. A lesson naming an anchor no view registered
draws its line with no caret, which is the safe way for that to fail.

**One guide, not two.** The island's own pointer, its line and its skip
chip are gone (126 lines), with the store's three first-hour helpers and
the two members of `FirstHourStep` that fed them. What survives of it is
`isDone(for:)`, which the lessons' goals call: the goal logic was written
against the save and proven, and a lesson must not grow a second opinion
about what "done" means.

**The library.** More → Lessons is `LessonsView`: every lesson by topic,
the given ones with a seal and replayable for ever, the locked ones named
and greyed. A replay is a CARD, never a pointer — the player may be
standing on the island reading the lesson about a relic slot, and a caret
aimed at a control that is not on this screen would be a caret that lies.
Skip marks the opening's lessons read plus a sentinel, so the carets stop,
the pop-ins carry on and the library keeps every word.

**Two checker rules came out of building it**, both refined rather than
silenced. The foreign-wrapped-property rule split the file by top-level
declarations, so an `extension View` mentioning a `store` parameter was
reported against whatever struct happened to be declared above it; an
extension is owned by nobody now, and an argument LABEL is not a read of
somebody else's property. Proven both ways: it still fires on a real
foreign read and is silent on a memberwise initialiser.

Tour steps 30 (`guide`, her plate over the island) and 31 (`lessons`) are
in the CI job. Still to come: the remaining pop-ins, the Counsel
checklist on `QuestService`, and the first battle that cannot be lost.

### The build it failed on, and the two rules that came out of it (2026-09-16)

The first push of all this (83d010f) went red, and both errors were the
kind this environment cannot see without a compiler:

1. `GameScreen { … }` — the screen takes a title, a `bar:` builder and a
   `content:` builder, and one bare trailing closure filled exactly one of
   them. Every other screen in the game writes it
   `GameScreen("More", subtitle: …, dismiss: …) { bar } content: { … }`;
   this one did not, and `swiftcheck`'s memberwise-init check could not
   see it, because a type with an explicit `init` is skipped there — which
   is every type in this project that takes a view builder.
2. `unseenIntroChapter` — the property was deleted along with the island's
   old guide and the one line that READ it stayed behind.

Both are now rules. **`check_required_arguments`** reads a single-init
type's explicit signature, counts how many parameters have no default,
and counts what a call actually supplies — parenthesised arguments plus
trailing closures, labelled or not. It is deliberately conservative: a
type with two inits is dropped, a type named in a return or annotation
position (`-> StatusSpec {`, `var x: StatModifier {`) is not a call, and
anything brace-shaped counts as supplied, so it under-reports rather than
cries wolf. **`check_lonely_identifiers`** flags a lowerCamelCase name
that the whole tree spells exactly once and reads as a value: a name a
type owns is written at least twice, once to declare it and once to read
it. Both were proven by putting the real bug back and watching them fire,
and both are silent on the tree as it stands. `strip_noise` grew a
`mask_strings` mode for the first of them — it deletes string literals by
default, which turns `LessonBeat("a sentence")` into a call with no
arguments at all.


### Built: the Night Market (2026-09-16)

The owner named it — "I like night market" — and it is the drachma sink the
game did not have. Before it, drachma had exactly ONE use, relic power-up,
and a currency with one sink stops meaning anything once a player has what
they want.

**A stall of the bazaar, not a building.** The bazaar already opens from the
wallet on the island and from More; a sixth landmark for a shop that changes
every hour would be a walk for nothing. `ShopService.Section.nightMarket`
sits beside Daily and Scrolls in the same dropdown, and `NightMarketBoard`
draws the shelf.

**The shelf is a SEED, not a list.** `Player.nightMarket` (Optional, as every
field added since the first must be) saves four things: the seed, the hour it
was rolled, the level it was rolled at, and which slots have been emptied.
`NightMarketService.stalls(for:)` derives the same six to ten wares from it
every time. A saved list of wares would put a relic in a second place — the
loadouts already taught this project that a relic lives in exactly one — and
would grow the save by a relic's worth of stats per slot per hour. Saving the
LEVEL with the roll matters too: without it, levelling up mid-hour would
change the shelf under the player's hand.

**Three things are deliberately not Summoners War's**, and each is a decision
rather than an omission:

1. **Slots are levels, never purchases.** Their Magic Shop sells slots for
   crystals, four rising to twelve. This game sells nothing for real money,
   so the six rise to ten at levels 10, 20, 30 and 40.
2. **No 5★ is ever on the shelf.** Their shop sells nat 3★ and, rarely, nat
   4★ monsters, and never a nat 5★. That is the line that keeps the gacha
   worth pulling, and it is the line here: 40,000 drachma for a 3★ and
   250,000 for a 4★ — a unit you can SEE, at a price the campaign has to pay
   for (5.4 and 34 full clears of chapter 1).
3. **A sold slot stays on the shelf, crossed out.** Theirs empties. A player
   should be able to see what tonight gave them and what they took.

**The engine is the re-roll.** A free refresh every hour on the same tick
that restores energy, and a paid one in divinity that climbs within a day and
resets with it: 30, 45, 70, 105, 155, 230, 345, 500. `balance.py --shop`
exists to check the one thing that must not be true — that chasing beats
buying. A Divine Scroll is on 5.6% of shelves, so about eighteen re-rolls to
find one: 5,980 divinity of re-rolls plus 430 to buy it, against 600 in the
bazaar outright. Ten times dearer, which is correct; eighteen hours of free
refreshes is the intended way. Every price is mirrored in `balance.py`
(`MARKET_WEIGHTS`, `MARKET_REROLLS`, `MARKET_SCROLL_PRICE`,
`MARKET_UNIT_PRICE`), with `DIVINITY_IN_DRACHMA = 300` read off the two
things the bazaar sells for both, so a drachma row can be judged against a
divinity one. The Mystical Scroll row is 24% DEARER at that rate than the
bazaar's 75 divinity, on purpose: it is the only way to buy a hard-currency
scroll with soft coin, and a premium is what stops it being a mint.

**`ShopService.Grant` grew a `unit(String)` case** for the rare row. A
duplicate becomes a skill-up exactly as a summon's does, so a second copy is
never clutter, and `ItemArt`'s four switches learned it — the tile draws the
unit's PORTRAIT with its grade's frame and star row, because the row is only
worth having if the player can see whose face is on the shelf.

**Athena's Night Market lesson is unlocked** (it shipped locked, as the
library's example of a thing the game still held): three stages into the Duat
she explains the hour, the coin and the price of not waiting. Tour step 32
photographs the shelf, opened straight on its stall through
`ShopView(opening:)` since nothing in a pinned tour taps a dropdown.

**A third checker rule, from the same day's red run.** The build went green
and the UNIT TESTS failed: `FirstHourStep.current(for:)` was trimmed as dead
code while `SaveGameTests` pins it, so the test target would not compile.
`check_static_members` should have caught it and did not — `current` was in
`SYNTHESISED`, the allow-list of members no source line declares
(`Calendar.current` and friends). It is out of that list now, the tree is
clean without it, and deleting the function again reports all seven call
sites. The helper is restored and says in its own comment why it survives:
nothing in the app calls it, and it is the one place the four first-hour
tests are asserted in order against a real save.


### The third red run, and two more rules (2026-09-16)

Adding `Grant.unit` broke the build in two places `swiftcheck` should have
seen, and both are rules now:

1. **`DungeonDatabase` switches over a Grant inside `for grant in granted`.**
   `check_switch_exhaustive` resolves the subject's type from the enclosing
   function's PARAMETER list, which is exact but blind to a loop variable
   whose type comes from a call's return. `check_switch_by_labels` covers
   that case by identifying the enum from the case LABELS instead. Name-only
   matching was tried on 2026-09-10 and was far too noisy, so it is held to a
   high bar: the labels must be a subset of exactly ONE enum, cover at least
   four of its cases and at least 70% of them, and that enum must have five
   or more. Nine of ten is a switch that has drifted; three of eight is a
   deliberate partial match over something else. Its first cut was silent on
   the very switch it was written for, because it collected every dotted name
   on a case LINE — `outcome.drachma`, `scroll.rawValue` — which put labels in
   the set that no enum has; it reads the case PATTERN only, up to the arm's
   colon.
2. **`ItemArt.amount(for:)` returns a plain `String`** and the new case was
   given `return nil`. `check_nil_returns` reads each function's declared
   return type and flags `case ...: return nil` inside one that is not
   Optional. Only a switch ARM, on one line: a bare `return nil` deeper in a
   body may belong to a closure, and this file would rather miss one than cry
   wolf.

Both proven by putting the real error back. A third thing was caught by eye
rather than by a rule and is worth writing down: `SeededRandom.pickWeighted`
takes `[(value:weight:)]`, and every other caller spells those labels out —
an unlabelled tuple literal is a conversion Swift does not always make.


### The fourth red run, and reading one cheaply (2026-09-16)

`fill(canReroll ? Theme.goldPlate : Theme.surface)` — `goldPlate` is a
LinearGradient and `surface` is a Color, and Swift will not unify them.
`ShopView`'s price plate has used a `Group { if … } else { … }` for exactly
this since it was written; the Night Market copied its shape without the
reason. `check_token_ternaries` reads each design token's type — off its
annotation, or off the name of the thing its initialiser calls, so
`static let surface = Color(hex:)` is a Color — and flags a `?:` whose two
branches are tokens of different types. Both sides must be known and must
differ, so it stays silent on the gold-or-grey Color ternary that is on
every screen. Proven by putting the real one back.

Also fixed by eye: `NightMarketBoard.columns` was a private STORED property,
and a private stored property drags the memberwise initialiser down to
private with it — `ShopView` builds the board from another file. It is a
type property now. (`ShopView`'s own `columns` gets away with being stored
because nothing ever passes it an argument: a struct whose every property
has a default also gets a DEFAULT `init()`, whose access level follows the
type rather than the properties.)

**And reading a red build is cheap now.** The GitHub log API serves only the
TAIL of a job. A compiler error sits near the top of a 550-line job whose
last 300 lines are the simulator booting through its data migration, so
finding one meant fetching the whole tail — three times over on this run,
and four times across the day. The job now writes `build-errors.txt` and
`test-errors.txt` to the `ci/screens` branch whether or not there are
frames, and `tools/ciframes.py` prints them before anything else. Four
lines over a git fetch, instead of five hundred over the API.


### Built: the rest of the Counsel (2026-09-16)

Three things finish the tutorial work and the shop.

**The first battle cannot be lost.** The owner's answer to the question was
"No", so `BattleEngine` gained one flag: `unloseable`, which floors a
PLAYER's combatant at 1 HP. It is checked before Endure, so a fight that
cannot be lost does not also spend the buff that would have saved the unit,
and `CampaignService.isTutorialFight` is the only thing that sets it — stage
id exactly `duat_1_1`, at Normal (a tier suffix is a different stage), on a
save that has never cleared it. Athena already says it out loud: "You cannot
lose this one. I have seen to it."

**Athena's Counsel, the road** (`CounselService`, the Counsel tab on the
Missions screen). Three tiers of ten — Initiate the first evening, Adept the
first week, Hierophant the long game — each step naming ONE next action in
the order a good player would take it, each paying, the tier gating the next
and ending in a prize of its own.

Two shape decisions worth keeping:

- It is deliberately NOT the feats list. Feats are forty unordered lifetime
  entries sorted by whatever is claimable; the Counsel is a road, and the
  screen shows **one tier at a time** with the tier's prize as its last row.
  Showing all thirty at once would be the feats list again, which is the
  thing this exists to replace.
- A tier opens when every step of the one before is DONE, not claimed.
  Gating on the claim would strand a player who cleared a tier and forgot to
  collect it — a wall the road exists to remove. The tier's own prize is the
  one thing that needs every step claimed, because it is the receipt for the
  whole tier.

Every step is `measure: (Player) -> Int`, read off the save, so nothing else
in the game has to know the Counsel exists and a veteran's save lands on the
right tier instead of at the beginning.

**`balance.py --counsel` caught a real fault and both sides of it were
wrong.** Its first run reported the road at **125% of the campaign** — and
the tier that did it was Hierophant, which handed out three Divine Scrolls
(600 divinity each in the bazaar) plus a Light & Dark: a checklist that is a
second gacha. But the denominator was also too narrow: twelve chapters of
FIRST CLEARS alone, leaving out the chests, the login gift and every tier
above Normal. So the tier was cut (6,562 down from 10,597; one Divine Scroll
on the whole road instead of four) AND the baseline now names everything it
counts — first clears, Normal chests, half the chapters on Hard, a month of
login gifts — and says in its own output that the daily missions are not in
it, so the figure is a floor and can be argued with. The road is 47% of that
now, which is a spine rather than a substitute.

**And the shelf is one row.** Run 151's frames showed the Night Market's six
slots drawn as five across and one alone beside a hole; the adaptive minimum
is 116 instead of 132, so a new player's six are one clean row and a level-40
summoner's ten are two. Tour step 33 photographs the Counsel, opened straight
on its tab through `MissionsView(opening:)` — the same trick as the bazaar's,
since nothing in a pinned tour taps a segmented control.

## The sweep (2026-09-16)

The owner asked for a batch of work while he tested, and for research into
"the top gatcha games that people are playing right now". That research is
`Docs/MARKET_2026.md`; this is the first thing built out of it, and it is
the item the report ranked second of ten.

**What the genre does.** Blue Archive lets a player sweep cleared content
instantly and take the drops without replaying it. Summoners War shipped its
own version in the **TOMORROW** update of November 2025 — **Scout Battle**,
which farms Cairos and the Rift **for up to eight hours while the app is
shut**, alongside Ameria's Luck, a daily 5x boost to high-grade drop rates.
Genshin and Honkai both sell an instant clear against the same stamina a run
would have cost. A 2026 round-up of the genre describes the modern shape as
"short dailies, generous sweep and auto features, and no punishment for
skipping a day".

**What this game had.** Auto-repeat, 1/5/10/20 runs — which still *plays*
every battle. Twenty runs of a three-wave Labyrinth level is seventeen
minutes of watching a fight whose outcome was settled the first time. That
was the genre's answer in 2014. The relic grind is the reason people leave
this kind of game, and a sweep is the single change that makes it survivable.

### The three ways to build it, and the one chosen

1. **Simulate headless.** Run the real `BattleEngine` N times with no scene,
   no animation, no HUD, and pay whatever the simulation returns. The truest
   of the three — a team that would lose, loses. It also costs twenty full
   three-wave simulations on the phone for a ×20, and the outcome is a
   foregone conclusion *by construction*, because of the gate below.
2. **Roll the rewards.** Skip the fight entirely and pay N clears. Instant,
   and it is what Blue Archive and Genshin actually do. On its own it lets a
   player who mastered Duat 1-5 at level 20 and has since fed his whole team
   to the Hall of Ka go on sweeping it forever.
3. **Hybrid** — simulate one battle to prove the current team still wins,
   then roll the other nineteen. One simulation's cost for most of (1)'s
   honesty.

**Chosen: (2), with a second gate the genre does not have.** A sweep needs
**three stars on this stage at this tier** — not a clear. A clear says you
beat it once, possibly by a hair with one unit standing; three stars says
everyone lived and it was inside the turn par, which is the same statement as
"the outcome of this fight is no longer in doubt". And the campaign team that
*would* have fought must still meet the stage's recommended power, which is
what closes the fed-my-team hole without a simulation. Between them the two
gates make (3)'s simulation redundant: it would be re-proving a fight the
save already records as mastered, against a team the screen has just checked.

It also gives the **star rating a job**. Until today it was pips on a
medallion. Now it is the key to the stage.

### What it is made of

- `SweepService` — the gates (`isMastered`, `isPowered`, `canSweep`), the
  refusal sentence, how many runs the energy pays for, and `masteredResult`,
  which builds the `BattleResult` a swept run is paid as: everyone alive,
  turns exactly at par. The three stars are not asserted — they are EARNED,
  by a result that satisfies the same `CampaignService.starRating` rule a
  fought run does.
- `CampaignService.settle` — new, and the reason this is safe. Everything a
  finished run does to the save (rewards, the star high-water mark, a tower
  floor's milestone, the quests) was inline in `GameStore.finishCampaignBattle`;
  it is one function now, and the sweep and the fight both go through it. A
  second way to clear a stage that pays through a second code path is a
  divergence waiting to happen.
- `GameStore.sweep(stage:runs:)` — checks the gates again (a screen can go
  stale, and this one spends energy), then loops: spend, settle, collect.
  Returns a `SweepReceipt` that keeps `runs` and `requested` apart, so a
  sweep that was asked for twenty and could afford eleven says so instead of
  quietly coming up short.
- `SweepButton` and `SweepReceiptCard` — the button sits beside Begin in the
  briefing's launch bar and on the stage popup, which is where the genre puts
  it, because the decision is "this stage, now, how many times" and a sweep is
  one of the answers to it. The button is dark most of the time by design, so
  it carries the sentence that says why ("Three-star this stage first — you
  have 2 of 3"). The receipt is the win's own `SpoilsPanel`, tiles and all:
  a sweep pays exactly what the fights would have paid, and a player who sees
  the same framed chest learns that without being told. `BattleSummary.loot`
  moved off the battle view model to a type method so both can draw it.

### What `balance.py --sweep` says

The economy does not move: the same energy, the same drops. A full 80-energy
bar refills in 6.7 hours at one per five minutes, so the cap on farming was
always the ENERGY and never the patience — which is exactly why a sweep is
safe to give away. What changes is the minutes: a bar of Duat 1-1 is 26 runs,
29 minutes fought and ten seconds swept.

There is **one** reward difference and the report names it rather than hiding
it: a sweep is always a three-star clear, so it always takes the ×1.25
drachma and unit-EXP bonus, where a sloppy auto-repeat that loses a unit takes
×1.00. Against the player the gate describes — one who has already
three-starred the stage — that is 0%. Against careless auto-repeat it is up to
25% more drachma, and that is intended.

Tour step 34 photographs it: a real sweep of `duat_1_1` on the tour's save,
the briefing behind and the chest in front.

## Mileage, the selector, and a pity counter that counts down (2026-09-16)

The market report's item 6 asked for four things. **Two of them were already
built**, and saying so is more useful than pretending otherwise: the summon
room's header has carried a live pity chip and a full published rate table
(`RateTableView`: every grade's odds and every name in the pool, plus the
Light & Dark discount, which is the one rate a player cannot work out from
the pool in front of him) since the premium pass. The App Store 3.1.1
compliance artefact the report asks for exists.

What did not exist is the half that matters most.

### The pity chip counts down now

It read "5★ 12/90". That is a fact about the past. Every published pity
tracker in the genre words it the other way — "guaranteed in 78" — because
that is the number the player is actually deciding on. One line changed, and
the detail behind the `?` leads with the same sentence.

### Mileage: a point a pull, and a unit you NAME

Pity stops a drought. It does not stop the WRONG five-star, which is the
complaint a hard pity cannot answer, and 2026 is being called the
guaranteed-banner era for exactly that reason: Blue Archive's 200
Recruitment Points buy the featured character outright, Epic Seven's Mystic
counter carries between banners without expiring, Genshin's Epitomized Path
lets a player commit to one of two weapons.

**Per banner, not one pool.** Blue Archive's points expire with the banner
and Epic Seven's do not, and the difference is that Blue Archive runs limited
banners. Every banner here is permanent, so per-banner points are never lost
— and a banner's points buying from that banner's own pool is what closes the
obvious hole: one global pool would let a player farm the cheap Unknown
Scroll and cash out a 5★ god, which is the exchange this is meant to be a
floor under, not a shortcut around. That exploit is closed by construction
rather than by a rule.

**And `balance.py --mileage` caught the price.** The first cut set a flat
divinity target — 15,000 for any 5★ — divided by what a pull of that banner's
scroll costs. On the pantheon banner that lands on 150, which is the genre's
own number and plainly right. Then the report printed the ratio it exists to
print: against the **hard pity**, that price was **0.62** on the Divine
Scroll and **0.28** on Light & Dark. On those two banners mileage would not
have been a floor under bad luck — it would have been the fast road, and the
pity counter beside it would have meant nothing.

The cause is that the divinity target is flat while the guarantee is not: a
Divine Scroll guarantees a 5★ in 40 pulls because its 5★ rate is 12%, where
Light & Dark takes 120. So the price is anchored to **the banner's own
counter**, at 1.7 times what that guarantee costs, with the divinity target
kept as a second floor underneath for the two banners that have no hard pity
at all — `max` of the two, so a unit is never cheaper than 1.7 guarantees and
never cheaper than its worth in divinity. Every banner now reads 1.70×, and
the report asserts it in its own output rather than leaving it to be read:

```
 banner scroll   a pull   5* pts   4* pts   3* pts    5* costs  hard pity   ratio
    pantheonic    100dv      153       61       21     15,300      9,000   1.70x
        divine    600dv       68       27       10     40,800     24,000   1.70x
    light_dark    450dv      204       82       28     91,800     54,000   1.70x
  the cheapest ratio on any banner is 1.70x -> correct
```

The exchange is a chip beside the odds and the pity in the summon room's
header, opening a board of the banner's own pool priced in points, dearest
first, so the thing a player is saving for is the first row. It says what the
rate is and how far off the target is, because a points system whose rate is
not printed is a points system nobody believes in.

### The selector: one 4★, chosen, on day one

Epic Seven's **Selective Summon** at account creation is credited as one of
its biggest free-to-play improvements. The point of it is not the unit — it
is that the first thing a player does in a gacha is a CHOICE, so the first
real face in his collection is one he wanted rather than one he was dealt.

Five candidates, one per element, **derived** from the 4★ tier of the Duat
rather than hand-written, so the shortlist cannot name a family whose cards
have not been painted; and sorted by id rather than rolled, so the five are
the same five every launch — a shortlist that changed under the player
between one look and the next would read as a bug. It opens itself the first
time he walks into the summoning circle, because a selector a player has to
go looking for is a selector most players never find. Never a 5★, once ever
(`Player.selectorClaimed`), worth 6,000 divinity-equivalent — about sixty
pantheon summons.

Tour steps 35 and 36 photograph both. The tour's save is given 118 points on
the Duat banner, so the exchange shows a 4★ that can be taken (61) beside a
5★ that cannot (153) rather than a board of identical refusals, and its
selector is marked spent — an unspent one would otherwise pop the gift sheet
over step 4's summoning room.

## Choice of two: the relic roll made an act, not an accident (2026-09-16)

The market report's item 3, and the one it argues hardest for. Worth stating
plainly why, because it is the only item that changes a system already
shipped rather than adding one.

**What the genre did this year.** Summoners War's **Reappraisal Stones**
reroll a Legendary rune's four sub stats keeping slot, set, main stat and
grade — and each roll **offers a choice between two options**. Its November
2025 update added **Refinement Stones** and **Core Fragments**, which "let
players power up their Runes and Artifacts **while keeping desired sub
properties**". Epic Seven's **Steel Workshop** crafts gear to a chosen set
and slot, and its **reforge** raises +15 gear from 85 to 90 with sub stats
"guaranteed to increase with a set value". Read together, that is the genre
leader spending a flagship update walking back the exact mechanic this game
copied: pure RNG with failure.

**What this game has.** `RelicService.upgradeOnce` rolls a sub stat at +3,
+6, +9 and +12 — adding one while there are fewer than four, otherwise
growing a random one — and the player watches. He pays 100·g² + level·… of
drachma per attempt and has a 40% chance of the attempt landing at +15.
Rune farming was the most-complained-about system in the genre for a decade
for exactly this shape.

**What is NOT wrong with it, and is invisible.** A failed attempt here has
never destroyed anything: it costs drachma and the level stays. Players
assume the worst because every game they have played before this one did
destroy something. That is a line of text on a screen, not a change.

### The design

1. **Two candidates at every sub-stat roll.** The attempt succeeds as it does
   now; then the screen offers two outcomes — "+ CRIT DMG 5.4%" beside "SPD
   +3 becomes SPD +7" — and the player takes one. This is the single change
   the report calls the one that converts rage into agency, and it is
   Summoners War's own reappraisal shape moved onto the roll that happens
   forty times more often.

2. **The offer is a SEED on the relic, not a stored pair.** `Relic` gets an
   Optional `pendingRoll: UInt64?`. The level goes up immediately; the two
   candidates are derived from that seed every time the screen is opened, so
   closing the sheet and coming back cannot reroll them. This is the Night
   Market's lesson applied again — a thing that exists in exactly one place
   is a seed, never a list — and it is what stops the choice being a free
   infinite reroll, which would be worse than no choice at all.

3. **A pending choice blocks the next attempt.** Otherwise a relic could sit
   at +12 with three choices stacked up behind it, and every screen that
   draws a relic would have to explain a half-rolled state.

4. **One new stone: the targeted reroll.** `RelicStone.Kind.chisel` —
   "reroll this ONE sub stat, keep the other three", which is the thing
   Refinement Stones do and the thing the existing gem does not (a gem
   REPLACES a sub with a new kind; a chisel keeps the kind and rerolls the
   value, with the better of the two kept). Three tiers like the others,
   dropping where the others drop.

5. **Say the failure rule out loud** on the power-up screen, in the same
   size as the odds: "A failed attempt costs drachma. It never takes your
   level or your sub stats."

### What it must not do

Not change the expected VALUE of a relic much. Two candidates is a
best-of-two, which raises the average roll — measured in `balance.py
--targeting`, which reports the mean sub-stat total at +12 under one roll and
under choice-of-two, so the drift is a number rather than a feeling. If the
lift is large the answer is to narrow the second candidate (offer the same
stat at a second value rather than a free second draw), not to abandon the
choice.

Built after run 153 lands; the research is written first because the owner
reads this file and because the seed-not-a-list decision is the one that
needed making before any code.

## More sub stats is the wrong lever; the drop table was the real bug (2026-09-16)

The owner asked two things: "Shouldn't we have more substats?" and "How do we
expand on the relics to be more like Summoners War (but with our own twist)?"
Then, on the answer: "we need RNG for everything no? Something that keeps
people playing and ALWAYS improving? also make sure theres a progression of
runes based on the difficulty of levels and all. Cant be giving 6 star relics
to easy matches."

### More sub stats would make the grind worse, not deeper

We already have **exactly Summoners War's eleven**: HP, HP%, ATK, ATK%, DEF,
DEF%, SPD, CRIT Rate, CRIT DMG, Accuracy, Resistance — and exactly its
main-stat rules, slots 1/3/5 fixed and 2/4/6 rolled. Summoners War has not
added a twelfth in twelve years, and the arithmetic says why. A relic drops
with at most four subs out of the ten left once the main stat is excluded:

```
11 sub stats (today)   one named sub 40.0%   a named PAIR 13.3%
12 sub stats           one named sub 36.4%   a named PAIR 10.9%
13 sub stats           one named sub 33.3%   a named PAIR  9.1%
15 sub stats           one named sub 28.6%   a named PAIR  6.6%
```

Every stat added dilutes every roll. A twelfth would cut the odds of the pair
a player is actually farming for by a fifth. The pool is not the gap.

### The drop table WAS the gap, and the owner named it

`balance.py --drops` is new and it ranks every source in the game by the power
it asks against the relic grade it pays. Its first run:

```
      chapter 1 boss hell    22,400     6*
     Hall of Essence B4      13,476     6*
            Labyrinth B9     22,870     5*   <- softer already paid 6
            Labyrinth B10    30,645     6*
```

Two real faults, both exactly what he described:

1. **`relicGradeFloor` was FLAT across all twelve chapters** — Hard floored at
   5★ and Hell at 6★ whether it was the Duat or the Dragon King's Gate. The
   first chapter of twelve, on its second tier, paid the same grade as the
   hardest content in the game. It is `relicGradeFloor(chapterOrder:)` now:
   Hard is `3 + (chapter - 1) / 3` and Hell one better, capped at 6. Chapter 1
   pays 3★ and 4★; chapter 7 reaches 6★ on Hell.
2. **The Halls of Essence out-dropped the Labyrinth.** Hall B4 paid a 6★ for
   13,476 power where Labyrinth B9 paid a 5★ for 22,870 — the *essence* farm
   beating the *relic* dungeon by a full grade at half the difficulty. Capped
   at 5★.

And one the audit found that he had not asked about:

3. **The Endless Tower under-paid at every floor.** `towerGrade` was
   `3 + (floor - 1) / 20`, so floor 50 — which this file's own notes say
   "falls to a maxed 6★ team" — paid a **5★**. The reward was a grade below
   the gear you had to be wearing to reach it, which is the one thing an
   endgame ladder must never do. It is `/16` now, which puts 6★ at floor 49.

**The result, measured:** the earliest 6★ in the game moved from Hall B4 at
**13,476** power to Tower F50 at **30,300** / Labyrinth B10 at **30,645** —
the two endgame ladders reaching 6★ at the same difficulty, within 1% of each
other, which is the shape that was wanted.

The report keeps ten "inversions" on its list and says they are expected: the
campaign's power curve (×26 by chapter 11) is on a different scale from the
dungeons', so a late chapter sits far right on the axis while paying 4★. That
is not a leak — the campaign is not the relic farm — but the numbers suggest
the late chapters' `powerScale` is inflated, which is its own question for
another day.

### On "we need RNG for everything"

He is right, and nothing here removes it. The relic system is already an
endless RNG treadmill — grade, quality (0–4 subs at the drop), which subs,
every roll's magnitude, the +15 gamble — and a better roll always exists.
What today's choice-of-two removed is not the randomness but the *insult*:
the dice still decide what is on the table, the player decides which of two.
That is the 2026 standard, not a softening.

What is genuinely missing for "ALWAYS improving" is a **ceiling above 6★**,
which is what Summoners War added in 2023 with Ancient runes: a tier with a
higher main-stat cap and better sub-stat ranges, from the hardest content
only. That is the next thing to build, and it is what makes the fixed drop
table above pay off — a progression that ends at 6★ for everyone eventually
has no top.

### The order the rest goes in

1. **Primordial relics** — the tier above 6★. Only from Tower 50+, Labyrinth
   B10, raids and chapter 8+ Hell. The answer to "always improving".
2. **Epithets** — one earned socket in the centre of the relic ring, holding a
   conditional line. The item is chosen; its magnitude still rolls and can be
   pushed, so the RNG is inside a thing the player picked.
3. **Pantheon resonance** — set bonuses that read the whole team.
4. **Artifacts** — the full second gear layer, last, because it doubles the
   inventory and that screen has been called overwhelming once already.

## Awakened relics and the Titans (2026-09-16, planned)

The owner, on the tier above 6★: *"Like an 'Awakened' Rune essentially? (without
having to awaken it)"* — and then: *"What about also adding some sort of beasts
you fight like the rift beasts that give you something towards something new?
(See summoners war rift beasts and the crystals they drop)."*

Those are one system, and his framing is better than the one this file proposed
an hour ago. Written up before any code, per the standing rule.

### Why "awakened" beats a 7★ grade

The earlier note here proposed **Primordial relics** as a new grade above 6★ —
Summoners War's Ancient runes. The owner's word for it is better for three
reasons, and the third is the one that decides it.

1. **It is already this game's vocabulary.** Units awaken. There is a rite for
   it in the Hall of Ka, a second card, a costume glow, an aura. A relic that
   awakens is the same idea in the same building with the same word.
2. **It costs almost no surface area.** A 7★ grade touches `Rarity`, every star
   row, the inventory's filters and its eight sorts, the optimiser, the drop
   tables and `balance.py --drops`. An awakened 6★ is a FLAG: same grade, same
   set, same slot, drawn with the awakened sun the cards already use plus a
   halo on the stone.
3. **It does not make the gear you own into junk.** This is the whole argument.
   A 7★ tier means every 6★ in the inventory is second-best the day it ships.
   An awakening is something you do TO a 6★ you already have, so the relic you
   spent a month getting to +15 becomes the INPUT rather than the casualty.

### What an awakening actually gives

- **A FIFTH SUB STAT.** Four is the cap today, here and in the whole genre —
  `RelicService` enforces it in five places. A fifth is the most coveted thing
  a relic could possibly gain and it needs no new grade to express.
- The +15 main stat ceiling goes from 3× to **3.6×** (`Relic.effectiveMainStat`).
- Nothing else changes: grade, set, slot, quality, the four subs it already has.

### Both roads to one, which is the point

The owner's "without having to awaken it" reads as *it drops that way*. Take
BOTH roads, because each alone has a hole:

- **It drops awakened**, rarely, from the hardest content. Lucky players get one.
  Alone, this is a 7★ by another name and rule 3 above fails.
- **You awaken one you own**, spending what the beasts drop. Patient players
  build one. Alone, there is no thrill of the drop.

Together: the drop is the dream, the awakening is the plan, and no 6★ is ever
wasted. That is also how Summoners War runs Ancient runes beside its craft
system.

### The Titans — our Rift Beasts

**What Summoners War's Rift of Worlds is.** Five elemental Rift Beasts, solo or
three-player co-op. The thing that makes them different from every other fight
is that you are **GRADED F to SSS on total damage dealt**, and the grade decides
the payout — you do not merely win, you win *by how much*. They drop elemental
**Crystals**, which gate the entire Craft Building, plus Grindstones and
Enchanted Gems for rune sub stats. The Rift Raid (R1–R5) sits beside them.

**What this game already has.** `RaidBossProfile` — a barrier that regenerates
and stuns when broken, guard adds that come back and drain the boss while they
live, enrage stacks on a clock, a rotating weakness — and raid stages
deliberately kept out of `chapters` so they cannot appear on the campaign map.
That is most of a beast fight already built.

**What is missing, and it is the interesting part:**

1. **A grade.** Every fight in this game is binary: cleared or not. A damage
   grade is the first fight you can get BETTER at, and it is what makes a beast
   worth farming after the first clear.
2. **A currency that comes from nowhere else.** Drachma has the Night Market,
   divinity has the bazaar; a crafting currency must have exactly one source or
   it is just another wallet line.
3. **Something to spend it on** — which the awakening above now is.

**The design.** Five **Titans**, one per element, older than the pantheons: the
things the gods put under the world. Each is fought on a clock, graded F→SSS on
total damage, and drops **Aether** — Ember Aether, Tide Aether, Gale Aether,
Radiant Aether, Umbral Aether, and a rare **Pure Aether** that any awakening
will take. An awakening wants aether of the relic's own SET colour plus pure,
so the five beasts are five different farms rather than one repeated.

That closes the loop: **the Titan is the source, the awakened relic is the
sink**, and neither exists without the other.

### The order, and what each phase costs

1. **The grade, on the raids that already exist** (~4 days). `RaidGrade` F→SSS
   off total damage in the turn limit, shown on the victory screen, deciding
   the payout. Aether drops here first. This tests the whole scoring loop
   against content already built, with no new art and no new place.
2. **Relic awakening in the Hall of Ka** (~1 week). The fifth sub stat, the
   3.6× ceiling, the halo on the stone, the aether cost, the rite reusing
   `AltarCeremony`. `balance.py --awakening` has to assert the one thing that
   must not be true: that an awakened relic makes an ordinary 6★ worthless.
   The target is that a well-rolled 6★ still beats a badly-rolled awakened one
   — the same shape Ancient runes have.
3. **The five Titans as their own place** (~1 week). New `BattleEnvironment`s,
   the beasts on `RaidBossProfile`, a wing of the Labyrinth or a sixth landmark.

**The cost that needs the owner's word.** Five beast meshes at 53 credits each
is **265**, and the Meshy balance is **1,891** against a floor of **2,000** —
that goes under. Phase 3 therefore ships with `ModelSpec.standInAsset`, which
already lets a boss fight as a giant of its kind (the Colossus stands in as a
4.5 m sentinel today), and the real meshes wait for either a top-up or his
explicit go. Nothing in phases 1 or 2 costs a credit or a cent.
