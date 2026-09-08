# Working agreements

## Answers

**Give exact, numbered steps.** When the answer involves doing something —
tool settings, a pipeline, a fix — write it as a numbered list of actions to
take in order, not as prose to interpret. Name the specific button, field,
value or filename. If there is a decision point, state the condition and both
branches rather than hedging.

Keep the reasoning, but put it after the steps or inline as a short "why",
never in place of them.

## This project

No Swift toolchain exists in the Claude Code environment — `download.swift.org`
is blocked by egress policy — so nothing here is ever compiled or run before it
is handed over. Two tools stand in and should be run before every commit:

```bash
python3 tools/swiftcheck.py --members --types   # argument order, labels, dead refs,
                                                # undeclared types, resource collisions
python3 tools/balance.py                        # stat curves, win rates, gacha odds
```

`--types` was noise-only until its allow-list covered the frameworks actually
used here; it is now clean and worth running. Every rule in the checker was
proven by reintroducing a real bug and watching it fail.

If a tuning constant changes in Swift, change it in `tools/balance.py` too. They
are kept in step by hand.

The 3D tools need packages that are not preinstalled. PyPI is reachable, so at
the start of a session that will touch models:

```bash
pip install -q usd-core numpy pillow scipy fast-simplification
```

## Where things stand

Read `Docs/PLAN.md` first. It has the measurements that decisions were based
on, the phase list, the pipeline costs, and an honest account of what this
environment can and cannot do. The short version:

- The game builds and runs on an iPhone. Battle, summon, collection, arena and
  campaign all work.
- Three families are in the code, and all three are complete: model, six
  clips and five portraits each, fifteen characters in the gacha. Anubis:
  natural 4★. Sekhmet: natural 5★, the first damage archetype. Zeus: natural
  5★, Greek, the control archetype (a Thunderclap that stuns, freezes, sleeps,
  knocks back or provokes the whole enemy line), with the "Olympus Stirs"
  banner live.
- Models ship **canonical and decimated**: `tools/mesh.py <family>` reads the
  untouched export in `Art/Models/` (Blender USDZ or Meshy GLB) and writes
  Y-up, metre, feet-on-origin, rest-equals-bind, four-influence files into
  `Pantheon/Resources/Models/` (3–4 MB per family), then re-skins them in numpy
  to prove it. The first Anubis export loaded as gold shards for five reasons
  listed in `Docs/PLAN.md`; the first Meshy file verified at 190 m tall for a
  sixth (the GLB reader assumed which frame the vertices were in; it now reads
  it off the joints). **Nothing has been confirmed on device** since the
  canonical rewrite, and Sekhmet and Zeus have never been seen; the first
  thing worth asking for is the `[ModelLibrary]` console block — the loader
  prints the bounding box and skinner it built.
- The app opens on the island (`IslandView`): five landmarks over the real
  painting. It was generated at 9:16 and its sea extended to 3:4, because a
  phone shows only the central 62% of the painting's width; the anchors were
  measured off it (`Docs/ART_2D.md` §6). `tools/island.py` is the stand-in
  painter, kept for reference.
- Portraits go through `BundleImage` (UIKit lookup). SwiftUI `Image("name")`
  drew nothing for loose bundle PNGs on device; never use it for one.
- The gacha pool is gated on shipped art (`UnitBlueprint.hasShippedArt`, a
  bundle lookup of `portrait_<id>.png`), which is why all fifteen are in it
  now with no code change. The battle camera is solved for a portrait phone
  (`BattleSceneController`); `tools/appicon.py` drew the icon.
- Meshy is driven from here. `tools/meshy.py` took Sekhmet and then Zeus from
  a prompt to a rigged model with six clips for 53 credits each, and
  `download` fetched the files once the host was opened; the task ids are in
  `Art/Models/*.meshy.json` and the untouched GLBs sit beside them.
- `tools/character.py` is the one place a rigged character is read (Blender
  USDZ or Meshy GLB), canonicalised, decimated, written and verified;
  `tools/mesh.py` runs a family through it, `tools/glb2usd.py` converts one
  file at full size. Two Meshy-specific facts live in the GLB reader: the
  vertex frame is recovered from the joints, and an emissive map that is the
  base colour is dropped (the game keeps real emissive maps, so shipping it
  would have made both characters self-lit).
- Art is done for all three families: 21 painted portraits, 5 stage backdrops,
  3 summon banners, the island painting, a particle sprite and a 10-texture UI
  kit. `tools/genart.py` makes more via Gemini; the key is provided as a
  credential, so it is in the environment and must never be printed or
  written to a file. Every prompt is in `Docs/ART_2D.md`; a family's five
  portraits are one generation plus four `--ref` edits, about two minutes.
- Sound is 14 synthesised effects (`tools/sfx.py`, thunder for Zeus) and two synthesised music
  loops (`tools/music.py`, island and battle), crossfaded by `AudioLibrary`.

### What this environment can reach

`api.meshy.ai` (with `MESHY_API_KEY` provisioned; task creation and polling
work), `assets.meshy.ai` and `cdn.meshy.ai` (finished files download),
`generativelanguage.googleapis.com` (with `GEMINI_API_KEY` provisioned as a
credential; image generation works, ~20 s an image), GitHub including
`raw.githubusercontent.com` (the Khronos sample rigs came from there), and the
package registries. **Not** `docs.meshy.ai`. Tripo, Rodin, OpenAI and Hugging
Face are refused by the environment's network policy with a 403 at CONNECT. Do
not try to route around a policy denial; report it.

To add a host: claude.ai/code → the cloud icon above the message box → hover
the environment → gear → **Network access: Custom** → list the domain →
**tick "Also include default list of common package managers"**. On Pro/Max,
**API credentials** in the same dialog is better for a keyed API: it opens the
host *and* keeps the key out of the session. Either way the change reaches
**new sessions only**.
