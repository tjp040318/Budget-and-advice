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
**3,000**; `wave_run.sh` reads the balance before every launch and counts
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

**Batch 3's families.** Egypt: Ra, Osiris, Ptah, Khnum, Nephthys, Ma'at,
Serqet, Taweret, Anhur, Bes, Medjay, Cobra Priestess. Greece: Hera,
Hephaestus, Demeter, Dionysus, Aphrodite, Nike, Achilles, Atalanta, Siren,
Nymph. Norse: Baldr, Frigg, Surtr, Njord, Idunn, Sif, Ullr, Vidar, Fenrir,
Bragi, Einherjar, Shield Maiden, Light Elf, Dark Elf. Every design is
described, never named as a likeness; every concept is an A-pose with the
weapon against the leg and both feet showing, the rigger's two demands.
