# Resource folders

Everything the app loads at runtime lives under `Pantheon/Resources/`. This file
documents all four folders in one place — deliberately, because of the trap
described at the bottom.

Every folder is optional. The game runs with `Pantheon/Resources/` completely
empty: models fall back to a procedural rig, portraits to an element-tinted
plate carrying the unit's initial, environments to a procedural platform in the
right colours, and audio is not wired up yet. **More → 3D assets** in the app
shows which characters are still standing in.

---

## `Models/`

`.usdz` files named after the unit's `assetName`. These are the **decimated**
files `tools/mesh.py` writes; the untouched Meshy exports live in `Art/Models/`,
outside `Pantheon/`, so they are never bundled. A raw export is 23 MB and a
family of them was 154 MB of app; what ships is 3 MB. Never copy a raw export in
here.

```
anubis.usdz                one file, and it serves all five elemental variants
anubis_lod.usdz            optional reduced mesh, used automatically in a 5v5
shabti.usdz
serpopard.usdz
sun_scarab.usdz
sandstone_sentinel.usdz
ammit.usdz
apep.usdz
```

The five Anubis — Ember, Tide, Gale, Radiance and Umbra — all point at `anubis`
and differ only by the aura colour `ModelLibrary.applyElementTint` washes over
their materials. One export covers the whole family.

Animation clips are loaded either from one file per clip:

```
anubis_idle_combat.usdz   anubis_attack_basic.usdz   anubis_attack_heavy.usdz
anubis_ultimate.usdz      anubis_hit_react.usdz      anubis_death.usdz
anubis_victory.usdz
```

…or from animation players embedded in `anubis.usdz` itself. `ModelLibrary`
tries the per-clip file first and falls back to the embedded player.

Only `anubis.usdz` is ever drawn. The per-clip files exist so
`ModelLibrary.animation(_:for:)` can lift a `CAAnimation` out of each; their
geometry and textures are read and discarded, so export those with textures off
if the tool allows it. `tools/mesh.py` takes care of it either way: clip files
come out at 1,500 triangles with a 128-pixel texture, about 150 KB each.

The Meshy prompt, export settings, polycount budget and the six ways this goes
wrong are in `ART_PIPELINE.md`.

## `Portraits/`

```
portrait_anubis_ember.png      1024x1024
portrait_anubis_tide.png       1024x1024
portrait_anubis_gale.png       1024x1024
portrait_anubis_radiance.png   1024x1024
portrait_anubis_umbra.png      1024x1024
portrait_shabti.png            1024x1024   (and the rest of the enemies)
banner_duat_opens.png          1284x800    summon banner splash
spark.png                       128x128    particle sprite, white radial on black
```

The five Anubis portraits can be recolours of one render — the same trick the 3D
side uses. `spark.png` upgrades every particle effect in the game the moment it
exists.

## `Environments/`

Two files per stage, named after the `BattleEnvironment` raw value:

```
duat_gate.scn            duat_gate_ibl.hdr
reed_fields.scn          reed_fields_ibl.hdr
hall_of_two_truths.scn   hall_of_two_truths_ibl.hdr
serpent_deep.scn         serpent_deep_ibl.hdr
arena_of_souls.scn       arena_of_souls_ibl.hdr
```

Keep the geometry inside a 30 m × 30 m box with the ground at y = 0. Do not add
lights — `BattleSceneController` supplies a key, a fill and an ambient, tinted
per environment from `keyLightHex` and `fogHex`. The IBL may be `.hdr` or
`.exr`; both are tried.

## `Audio/`

Not wired up yet. When it is: `sfx_<event>.caf` for effects and
`music_<screen>.m4a` for loops.

---

## Why this is one file and not four

`Pantheon.xcodeproj` is `objectVersion = 77` and uses
`PBXFileSystemSynchronizedRootGroup`, so every non-source file under `Pantheon/`
is added to the target automatically — and **copied flat into the app bundle**,
losing its folder. Four `README.md` files in four resource folders all resolve to
`Pantheon.app/README.md`, and the build fails with:

```
Multiple commands produce '.../Pantheon.app/README.md'
```

That is the whole reason this documentation sits in `Docs/` instead. The same
trap applies to any two resources sharing a basename — `spark.png` in two
folders, `duat_gate.scn` duplicated, and so on.

`tools/swiftcheck.py` checks for it (rule 8) and fails the run if it recurs.

The flattening also means folder names are not part of the runtime path.
`ModelLibrary.bundleURL(for:)` asks for `subdirectory: "Models"` first and then
retries with no subdirectory, which is the lookup that actually succeeds;
`BattleSceneController` does the same for `Environments`. Leave both in place.

Because git does not track empty directories, `Portraits/`, `Environments/` and
`Audio/` do not exist in a fresh clone. Create the folder when you add the first
file to it — nothing needs to be registered anywhere afterwards.
