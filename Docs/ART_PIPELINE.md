# Art pipeline — Meshy to the game

This is the contract between the 3D work and the code. Every filename and node
name below is something `ModelLibrary` actually looks for at runtime, and the
**More → 3D assets** screen in the app shows a green dot the moment a file is
found.

Nothing here blocks you. Every character without a model gets a procedural
placeholder rig — correctly sized for its archetype, tinted to its element,
exposing the same attachment nodes a real rig does. Combat, cameras, VFX and
every screen are finished and testable with an empty `Models/` folder.

---

## 1. The headline: one model covers five characters

The Anubis family is five summonable units — Fire, Water, Wind, Light and Dark —
and they are **one mesh**. Every variant points at `assetName: "anubis"` and
differs only by `auraHex`, which the renderer uses to tint the rim light, the
aura core, the ground ring and the summon beam.

That is how the genre affords a roster of hundreds, and it means the art cost of
your entire first family is **a single Meshy export**.

So the whole minimum delivery is:

| File | Folder | Notes |
|---|---|---|
| `anubis.usdz` | `Pantheon/Resources/Models/` | Rigged, 2.05 m, Y-up, facing +Z, origin at the feet |
| `portrait_anubis_umbra.png` | `Pantheon/Resources/Portraits/` | 1024×1024 |
| `portrait_anubis_ember.png` … and the other three | same | Recolours of the same portrait are fine |
| `banner_duat_opens.png` | same | 1284×800 splash |
| `spark.png` | same | 128×128 white radial glow — upgrades every particle effect |

Enemy models (`shabti`, `serpopard`, `sun_scarab`, `sandstone_sentinel`,
`ammit`, `apep`) are optional and can come later, one at a time.

---

## 2. The prompts

### Route A: straight to Text-to-3D

Paste this into **Text to 3D**. It is written the way Meshy responds best: one
subject, described head to feet, with the pose and the materials stated and the
scene explicitly removed.

> **Prompt**
>
> ```
> Full body game character of Anubis, the Egyptian jackal-headed god of the
> dead, standing upright in a symmetrical A-pose with arms lowered and held
> away from the body, legs straight and shoulder-width apart, facing forward.
> Sleek matte-black jackal head with a long narrow muzzle and tall upright
> pointed ears, pale glowing eyes. Athletic humanoid male body with dark
> bronze skin. Wearing a pleated white linen kilt with a gold waistband, a
> broad ornate gold and lapis-lazuli usekh collar covering the chest and
> shoulders, gold armbands at the biceps, and gold anklets. A striped nemes
> headcloth falls behind the ears onto the shoulders. Hands open and empty,
> fingers separated, holding nothing. Polished gold jewellery, matte cloth,
> soft semi-gloss skin. Even neutral lighting, plain empty background,
> character only, standing directly on the ground with no base.
> ```
>
> **Negative prompt**
>
> ```
> staff, spear, weapon, scales, props, base, pedestal, plinth, stand,
> background, scenery, hieroglyphs, text, watermark, two characters, wings,
> extra limbs, crossed arms, arms raised, floating, cape, flowing cloth
> ```

**Why it is written that way**

- **A-pose, arms away from the body.** Both Meshy's own rigging and Mixamo want
  limbs clear of the torso. Arms tight to the body fuse in the mesh and the
  auto-rig fails at the shoulder.
- **"Hands open and empty, holding nothing."** A generated staff welds itself to
  the hand and to the rig. The game attaches VFX to `hand_r`, so the hand needs
  to be a hand.
- **"No base, no pedestal."** Generators love adding a display plinth. It becomes
  geometry at the feet, the origin lands inside it, and the character floats.
- **"Plain empty background, character only."** Anything else becomes mesh.
- **The jackal head is doing real work.** Image-to-3D tools are at their worst on
  human faces. An animal head *is* the silhouette, so the weakest part of the
  technology never appears. This is a large part of why Anubis is the right
  character to start with.

**Settings**

| Setting | Use | Why |
|---|---|---|
| Art style | Stylized if offered, otherwise Realistic | The genre reads stylized; realistic scans look wrong beside synthesized VFX |
| Symmetry | On | It is a symmetrical character and this markedly improves limbs |
| PBR / textures | On, 2048 | The renderer forces physically-based shading on import |
| Target polycount | 30k–40k triangles | Ten characters on screen on a phone |
| Topology | Quad, if the remesh step offers it | Deforms far better when animated |
| Export | **USDZ** (GLB and FBX also work) | USDZ is SceneKit's native path |

Generate, then use the **refine / high-quality** pass before exporting — the
preview mesh is not good enough to rig.

### Route B: generate a concept image first, then Image-to-3D

Usually the better path for a character. You art-direct in 2D, where a bad
result costs seconds, and only convert once the silhouette is right.

The image prompt is **not** the same as the text-to-3D prompt. Three clauses
exist only because a 2D image is about to become geometry and texture:

- **Flat, shadowless lighting.** Whatever lighting is in the image is baked into
  the model's texture. A dramatic rim light becomes a permanent white stripe
  that cannot be relit. This is the most common image-to-3D mistake.
- **Orthographic front view.** Perspective distortion becomes wrong geometry — a
  slightly low camera gives a model with oversized feet.
- **Plain mid-grey background.** Contrasts with both the black head and the white
  kilt, so background removal does not eat the silhouette. White or black each
  lose one half of him.

> **Image prompt**
>
> ```
> Full-body character concept of Anubis, the Egyptian jackal-headed god of
> the dead. Straight-on front view, orthographic, no perspective distortion,
> camera at chest height. Symmetrical A-pose: arms lowered and held away from
> the body with a clear gap at the armpits, palms facing the thighs, fingers
> separated, legs straight and shoulder-width apart, feet flat.
>
> Sleek matte-black jackal head, long narrow muzzle, tall upright pointed
> ears, pale glowing eyes. Athletic humanoid male body, dark bronze skin.
> Pleated white linen kilt with a gold waistband. Broad ornate gold and
> lapis-lazuli usekh collar across the chest and shoulders. Gold armbands at
> the biceps, gold anklets. Striped nemes headcloth falling behind the ears
> onto the shoulders, close to the head. Hands open and completely empty.
>
> Flat even studio lighting, no cast shadows, no rim light, no dramatic
> contrast. Plain solid mid-grey background. Whole figure visible with margin
> above the head and below the feet. Sharp focus throughout, no depth of
> field.
> ```
>
> **Negative prompt**
>
> ```
> staff, spear, weapon, scales, ankh, props, held objects, base, pedestal,
> plinth, ground shadow, background scenery, hieroglyphs, text, watermark,
> two characters, wings, cape, flowing fabric, arms raised, arms crossed,
> dynamic pose, three-quarter view, low angle, dramatic lighting
> ```

**Image generator settings**

| Setting | Use | Why |
|---|---|---|
| Model | The highest-adherence tier available | This prompt holds eight hard constraints at once. That is a prompt-adherence problem, not an aesthetics one — spend the good tier on the image you will actually convert, and use a cheap tier to explore silhouettes |
| Aspect ratio | **3:4** | A-pose arms make the figure about 0.6x as wide as tall, so 3:4 frames it with margin. 9:16 clips hands or shrinks the figure |

Generate three or four and choose on **silhouette clarity and the gap under the
arms**, not on which looks prettiest. A render with the arms touching the torso
is worthless here however good it looks — the auto-rig will fail at the shoulder.

Then feed the chosen image to Meshy's Image-to-3D and continue from step 2 of the
pipeline below.

### Reviewing the mesh before you texture it

Generate the **untextured mesh first**. Texturing is the slow half, and the risk
in this pipeline is geometry: a model whose arms welded to its ribs is unriggable
and no texture repairs it. A good mesh can always be re-textured; a good texture
cannot be re-meshed.

That trade is even more lopsided here than usual, because the five elemental
variants share one mesh and differ only by an aura tint. The geometry is doing
five characters' worth of work; the base texture only has to be neutral enough
to accept a tint.

Check in this order. The first three are pass/fail:

1. **Armpit gap.** Actual separated surfaces, or did the arms weld to the ribs?
2. **Between the legs.** Same question. A fused crotch kills the hip rig.
3. **The back.** Single-image conversion *invents* everything it cannot see, and
   the back of the head and the fall of the kilt are where it shows. Orbit the
   model before committing.
4. **Fingers.** Separated, or one mitten? A mitten is survivable for a game
   character at this scale; fused arms are not.
5. **Ears.** Distinct, or melted into the skull silhouette?
6. **Feet.** Flat on the ground plane, and no invisible pedestal underneath.

If 1–3 are clean, texture it. If any failed, re-roll the mesh from the same
image before touching the prompt — a concept that already passed the 2D checks
is not the problem.

### Decimate before anything else

Image-to-3D returns a **sculpt, not a game asset**. The first Anubis conversion
came back at 3,080,176 faces and 1,540,088 vertices against a budget of 15k–40k
triangles — about seventy-seven times over.

That is not a stylistic quibble. 1.54M vertices is roughly 110 MB of vertex and
index data for one character; ten of them in a 5v5 is over a gigabyte before a
single texture loads. It will not run, and it will not load.

**Remesh to ~30k triangles before doing anything else**, and take quad topology
if the tool offers it — edge loops around the shoulder and hip deform
predictably, whereas triangle soup pinches once the character is animated.

The order is not negotiable, because each step invalidates the last:

1. **Remesh to ~30k.** Quad if offered.
2. Re-check the silhouette survived — especially fingers and ears.
3. **Then** texture, at 2048.
4. **Then** rig.
5. Export USDZ.

Rig first and decimate after, and the skin weights are destroyed. Texture first
and decimate after, and the UVs are invalidated and the bake is wasted.

If the tool's remesh will not go low enough, Blender's Decimate modifier at a
0.01 ratio takes 3M to 30k in one pass. Either way some surface detail is lost —
kilt pleats, muscle definition. On a phone, where the character stands a few
hundred pixels tall, that detail was never visible.

### Conversion settings

Worth writing down, because these get repeated once per character family.

| Setting | Geometry pass | Texture pass |
|---|---|---|
| Model | Latest available | Latest available |
| Quality | Highest tier | Highest tier |
| Generate texture | **Off** | On |
| Texture size | *(no effect — ignore it)* | **2048** |

The highest quality tier earns its cost on the geometry pass specifically: it is
the pass that decides whether the model can be rigged at all, and one mesh
carries all five elemental variants.

**2048, not 4096.** A 4096 map is 64 MB uncompressed and roughly 8–16 MB after
iOS texture compression. A PBR character wants base colour, normal and
roughness/metal — three or four maps — so 4096 is about 48 MB per character
against a 24 MB budget, with up to ten characters on screen. At 2048 it is around
12 MB and comfortable. The on-screen argument agrees: the character occupies a
few hundred pixels even in a cinematic push-in, so 4096 buys texel density the
display cannot resolve.

The one reason to generate at 4096 is to keep a master for hand-editing the five
colourways. In that case keep it in the art source and downsample to 2048 for the
bundle.

### The five elemental variants

You do not need five models. If you want five distinct *textures*, re-run only
the texturing step on the same mesh with a colour line appended:

| Variant | Append to the prompt | `auraHex` in code |
|---|---|---|
| Fire | "black and molten-orange, glowing ember cracks in the collar" | `#F2703C` |
| Water | "black and deep blue, wet lacquered surfaces, turquoise inlay" | `#3C9BF2` |
| Wind | "black and pale jade, weathered sand-scoured gold" | `#4FC98A` |
| Light | "black and white gold, sun-disc motifs, bright polished surfaces" | `#F5D96B` |
| Dark | "black and dark silver, cold teal glow in the eyes and collar" | `#7FE0C8` |

If you skip this entirely the game still ships five visually distinct units.
`MaterialTuner.applyElementTint` copies each instance's materials and multiplies
them by a mostly-white wash biased toward the element colour, so the gold stays
gold and the linen stays linen while the whole figure reads warm, cold or pale
across a board. Do the per-element textures when you have time, not before.

**You do need one texture, though.** Untextured, the tint has nothing to tint:
all five variants render as the same grey statue with differently coloured
ground rings. One textured export is the minimum, and it covers the family.

---

## 3. Getting from Meshy to the game

1. **Generate** with the prompt above. Refine, then export.
2. **Rig.** If your Meshy plan includes rigging and animation, use it — it is
   built for exactly this humanoid shape. Otherwise export FBX and run it
   through **Mixamo**, which auto-rigs and gives you the clip library free.
3. **Rename the clips** to the exact names in the table below.
4. **Check the transform in Blender**: real metres, origin between the feet on
   the ground plane, facing +Z, all transforms applied.
5. **Convert to USDZ** — Apple's Reality Converter, Blender's USD exporter, or
   `usdzconvert`.
6. **Drop it in** `Pantheon/Resources/Models/`. The dot on the asset screen
   turns green. No code change.

### Animation clips

Exact names. The loader looks them up by these strings, and anything missing
falls back to procedural motion, so partial delivery is fine.

| Clip | Loops | Length | What it is |
|---|---|---|---|
| `idle` | yes | 3–5 s | Out of combat |
| `idle_combat` | yes | 2–4 s | Combat stance — plays 90% of the time |
| `attack_basic` | no | ~1.0 s | Jackal's Due. Contact at ~45% |
| `attack_heavy` | no | ~1.4 s | Weighing of the Heart |
| `cast_loop` | yes | 1–2 s | Channel |
| `cast_release` | no | ~1.4 s | Release out of a channel |
| `ultimate` | no | ~2.4 s | Opening of the Mouth. The rite |
| `hit_react` | no | ~0.45 s | Flinch. Must not move the root |
| `death` | no | ~1.2 s | Collapse |
| `victory` | no | ~2.0 s | Survivors, on a win |
| `summon_reveal` | no | ~3.0 s | Slow hero turn, for the summon screen |

**No root motion.** The engine owns positions; a clip that translates the root
slides the character off its stage slot. Loops must be seamless. 30 fps is fine.

### Rig node names

Used as VFX attachment points. Different names are fine — send them and they go
into the character's `ModelSpec`.

`hand_r` · `weapon_r` · `spine_03` · `head`

---

## 4. What goes wrong, and what it looks like

| Symptom in game | Cause |
|---|---|
| Character is tiny or enormous | Exported in centimetres, not metres |
| Sinks into the floor or floats | Origin at the hips or the bounding-box centre — or a pedestal came along |
| Faces away from the enemy | Model faces −Z; set `yawCorrection: 180` in its `ModelSpec` |
| Untextured / white | Textures not embedded in the `.usdz` |
| Flat and plasticky | Lighting baked into the base colour map |
| Animations do not play | Clip names do not match the table exactly |
| Shoulders tear when animated | Arms were too close to the torso in the source pose |

---

## 5. Budgets

| Thing | Budget |
|---|---|
| Triangles per character | 15k–40k (a primordial like Apep may go to 70k) |
| Characters on screen | 10 (5 v 5) |
| Total scene triangles | Under 400k |
| Texture memory per character | Under 24 MB |
| Target frame rate | 60fps on iPhone 12 and newer |

## 6. Heights

These drive camera framing and health-bar placement, so a wrong height reads as
a bug rather than as a choice.

| Archetype | Height | In this roster |
|---|---|---|
| Spirit | 1.7 m | Shabti |
| Hero / Demigod | 1.8–1.9 m | — |
| God | 2.0–2.2 m | **Anubis, 2.05 m** |
| Monster | varies | Serpopard, Ammit, Sentinel |
| Titan | 3.0–4.0 m | — |
| Primordial | 4.5 m+ | Apep, 3.6 m |
