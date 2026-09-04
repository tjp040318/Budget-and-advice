# Battle stages

Two files per environment:

```
olympus_peak.scn        olympus_peak_ibl.hdr
marble_court.scn        marble_court_ibl.hdr
storm_altar.scn         storm_altar_ibl.hdr
tartarus_gate.scn       tartarus_gate_ibl.hdr
arena_colosseum.scn     arena_colosseum_ibl.hdr
```

Keep the geometry inside a 30 m × 30 m box with the ground at y = 0. Do not add
lights — the renderer supplies a key, a fill and an ambient, tinted per
environment.

Every stage falls back to a procedural platform in the right colours, so none of
these are required to ship.
