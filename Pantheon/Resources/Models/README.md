# Character models

Drop `.usdz` files here, named after the unit's `assetName`:

```
zeus.usdz
cerberus.usdz
menoetius.usdz
harpy.usdz
naiad.usdz
bronze_automaton.usdz
shade_tartarus.usdz
```

Optionally, one file per animation clip instead of embedding them:

```
zeus_idle_combat.usdz
zeus_attack_basic.usdz
zeus_attack_heavy.usdz
zeus_ultimate.usdz
zeus_hit_react.usdz
zeus_death.usdz
zeus_victory.usdz
```

Full specification — scale, orientation, materials, rig node names, animation
clip list and the 3D AI Studio → Blender → Mixamo → USDZ route — is in
`Docs/ART_PIPELINE.md`.

Anything missing is replaced by a procedural placeholder at runtime, so the game
runs with this folder empty. Check **More → 3D assets** in the app to see which
characters are still on placeholders.
