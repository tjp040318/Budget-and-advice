# Character models

Drop `.usdz` files here, named after the unit's `assetName`:

```
anubis.usdz                one file, and it serves all five elemental variants
shabti.usdz
serpopard.usdz
sun_scarab.usdz
sandstone_sentinel.usdz
ammit.usdz
apep.usdz
```

The five Anubis — Fire, Water, Wind, Light and Dark — all point at `anubis` and
differ only by the aura colour the renderer tints them with. One export covers
the whole family.

Optionally, one file per animation clip instead of embedding them:

```
anubis_idle_combat.usdz   anubis_attack_basic.usdz   anubis_attack_heavy.usdz
anubis_ultimate.usdz      anubis_hit_react.usdz      anubis_death.usdz
anubis_victory.usdz
```

The Meshy prompt, the export settings, the animation clip contract and the six
ways this goes wrong are all in `Docs/ART_PIPELINE.md`.

Anything missing is replaced by a procedural placeholder at runtime, so the game
runs with this folder empty. **More → 3D assets** in the app shows which
characters are still standing in.
