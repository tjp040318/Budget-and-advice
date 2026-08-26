# Art pipeline — what the game needs from you

This is the contract between the 3D work and the code. Every filename, unit and
node name below is something the app actually looks for at runtime. Nothing here
is aspirational: `ModelLibrary` searches for these exact names, and the **More →
3D assets** screen in the app shows a green dot the moment a file is found.

If an asset is missing the game still runs — it substitutes a correctly-sized,
correctly-tinted placeholder rig. So you can deliver these one at a time, in any
order, and see each one appear without a code change.

---

## 1. The short answer: files needed for Zeus

Drop these into `Pantheon/Resources/`:

| File | Folder | What it is |
|---|---|---|
| `zeus.usdz` | `Models/` | Rigged character with animation clips embedded |
| `portrait_zeus.png` | `Portraits/` | 1024×1024 square portrait for cards |
| `banner_olympus_rising.png` | `Portraits/` | 1284×800 splash for the summon banner |
| `spark.png` | `Portraits/` | 128×128 white radial glow for particles |
| `olympus_peak.scn` | `Environments/` | Battle stage (optional — procedural fallback exists) |
| `olympus_peak_ibl.hdr` | `Environments/` | Environment lighting for that stage |

That is the whole minimum. Everything else in the game is already built.

If you would rather ship animations as separate files than embed them, name them
`zeus_idle_combat.usdz`, `zeus_attack_basic.usdz`, and so on — the loader checks
that layout too.

---

## 2. Model specification

### Geometry

| Property | Requirement |
|---|---|
| Format | `.usdz` (preferred), `.usdc`, `.scn`, or `.dae` |
| Up axis | **Y-up** |
| Forward axis | **+Z** (the character faces +Z; if yours faces −Z, say so and it is corrected in one line of data, not in the mesh) |
| Units | **Metres.** Zeus is **2.05 m** tall — see the height table below |
| Origin | **Between the feet, on the ground plane.** Not at the hips, not at the centre of the bounding box |
| Triangles | 15k–40k for a god or hero. Up to 70k for a Titan. This is a phone |
| UVs | One UV set, no overlapping islands on the base layer |
| Scale in file | 1.0. Do not pre-scale to compensate for anything |

**Heights the game expects.** These drive camera framing and health-bar placement,
so a wrong height reads as a bug rather than as a stylistic choice:

| Archetype | Height |
|---|---|
| Spirit | 1.7 m |
| Hero / Demigod | 1.8–1.9 m |
| God | 2.0–2.2 m |
| Monster | varies — state it |
| Titan | 3.0–4.0 m |
| Primordial | 4.5 m+ |

### Materials

Physically-based, one material per logical surface, four or fewer materials per
character:

| Map | Resolution | Notes |
|---|---|---|
| Base colour | 2048² | sRGB. No baked lighting, no baked ambient occlusion in the albedo |
| Normal | 2048² | Tangent space, OpenGL convention (+Y up) |
| Roughness | 1024² | Linear. Keep the used range roughly 0.2–0.9 |
| Metalness | 1024² | Linear. Mostly 0 or 1; avoid grey metal |
| Emissive | 1024² | Only where something actually glows — eyes, runes, the bolt |
| Ambient occlusion | 1024² | Optional, separate map, never multiplied into base colour |

Textures must be **embedded in the `.usdz`**. Loose sidecar textures will not be
found.

The renderer clamps roughness into a sane band and forces PBR shading on import
(`MaterialTuner`), so a slightly hot export will still look right — but a base
colour with lighting baked into it cannot be rescued.

### Rig

Any skeleton works, but these node names are used as VFX attachment points. If
your rig uses different names, they can be remapped in the character's
`ModelSpec` — send the names you used.

| Node | Purpose |
|---|---|
| `hand_r` | Right-hand effects — the bolt spawns here |
| `weapon_r` | Weapon socket, if the character holds one |
| `spine_03` | Chest-level effects, auras, the summon beam anchor |
| `head` | Above-head markers |

Bone count under 90 keeps the GPU skinning path fast.

---

## 3. Animation clips

Every character needs these. Clip names must match exactly — the code looks them
up by these strings.

| Clip name | Loops | Length | What it is |
|---|---|---|---|
| `idle` | yes | 3–5 s | Out-of-combat breathing idle |
| `idle_combat` | yes | 2–4 s | Combat stance. This is what plays 90% of the time |
| `attack_basic` | no | ~1.0 s | The basic attack. Contact at roughly 45% through |
| `attack_heavy` | no | ~1.4 s | The cooldown skill. Bigger wind-up, contact at ~50% |
| `cast_loop` | yes | 1–2 s | Channelling pose, for held casts |
| `cast_release` | no | ~1.4 s | The release out of a channel |
| `ultimate` | no | ~2.4 s | The big one. Zeus rises, the sky opens, it lands |
| `hit_react` | no | ~0.45 s | Flinch. Must not move the root |
| `death` | no | ~1.2 s | Collapse. Ends lying down; the model then fades |
| `victory` | no | ~2.0 s | Plays for survivors when the battle is won |
| `summon_reveal` | no | ~3.0 s | Slow hero turn, for the summoning screen |

Rules that matter:

- **No root motion.** The engine owns positions. A clip that translates the root
  will slide the character off its stage slot.
- **Loops must be seamless** — first frame equals last frame.
- **30 fps** is plenty. 60 if the clip is fast.
- One-shot clips return to the `idle_combat` pose on their final frame, so the
  blend back is invisible.

If a clip is missing, the placeholder motion for it plays instead — the battle
keeps its timing, it just looks rough. So partial animation delivery is fine.

---

## 4. Getting there from 3D AI Studio

3D AI Studio produces good static meshes; it does not rig or animate. The route
that works:

1. **Generate** in 3D AI Studio. Prompt for a T-pose or A-pose, full body, arms
   away from the torso. Export **GLB** or **FBX** at the highest quality tier.
2. **Clean up in Blender.** Check scale (set it to real metres), move the origin
   to between the feet, apply all transforms, face +Z, and decimate to the
   triangle budget if the generator overshot. Retopologise the hands if they came
   out as a blob — auto-rigging fails on fused fingers.
3. **Rig.** Upload the cleaned FBX to **Mixamo**, auto-rig it, and download the
   animation clips you need. Mixamo's library covers idle, attack, hit reaction,
   death and victory well enough to ship a first pass; the ultimate is usually
   worth hand-animating.
4. **Rename the clips** to the exact names in the table above.
5. **Convert to USDZ.** Either Apple's **Reality Converter** (drag the FBX in,
   check the materials, export), Blender's USD exporter, or `usdzconvert` from
   Apple's USD Python tools.
6. **Drop it in** `Pantheon/Resources/Models/` and run the app. The dot on the
   **More → 3D assets** screen turns green.

Common failures, and what they look like in game:

| Symptom | Cause |
|---|---|
| Character is tiny or enormous | Model exported in centimetres instead of metres |
| Character sinks into the floor or floats | Origin is at the hips or the bounding-box centre |
| Character faces away from the enemy | Model faces −Z; set `yawCorrection: 180` in its `ModelSpec` |
| Model appears untextured / white | Textures were not embedded in the `.usdz` |
| Model looks flat and plasticky | Lighting was baked into the base colour map |
| Animations do not play | Clip names do not match the table exactly |

---

## 5. 2D assets

| Asset | Size | Notes |
|---|---|---|
| `portrait_<unit>.png` | 1024×1024 | Head-and-shoulders, framed for a square crop. Transparent or dark background |
| `banner_<banner_id>.png` | 1284×800 | Summon banner splash. Keep the left third clear — the title sits there |
| `spark.png` | 128×128 | White radial falloff on black, premultiplied alpha. Every particle effect uses it |
| `AppIcon` | 1024×1024 | Into `Assets.xcassets/AppIcon.appiconset` |

Portraits are optional — cards fall back to an element-tinted plate with the
unit's initial, which is ugly but functional.

---

## 6. Environments

Each `BattleEnvironment` case wants two files:

| File | Notes |
|---|---|
| `<name>.scn` | The stage geometry. Keep it inside a 30 m × 30 m box; the camera never leaves it. Ground plane at y = 0 |
| `<name>_ibl.hdr` | Equirectangular HDR, 2048×1024, for reflections and ambient light |

Currently referenced: `olympus_peak`, `marble_court`, `storm_altar`,
`tartarus_gate`, `arena_colosseum`. All five fall back to a procedural platform
tinted with that environment's colours, so the game is playable with none of them.

Stages need no lighting of their own — the code adds a key light, a fill and an
ambient, and tints them per environment.

---

## 7. Budgets

The whole point of these numbers is that a battle can have nine characters on
screen at once on a phone that is also running the particle systems.

| Thing | Budget |
|---|---|
| Triangles per character | 15k–40k (Titans to 70k) |
| Characters on screen | 10 (5 v 5) |
| Total scene triangles | Under 400k |
| Texture memory per character | Under 24 MB |
| Draw calls | Under 150 |
| Target frame rate | 60 fps on iPhone 12 and newer, 30 fps floor on older devices |

If a character needs to break these, say so — some do, and the fix is usually a
lower-detail variant used when more than four are on screen.
