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
- Three families are in the code. Anubis: five variants, natural 4★, full art.
  Sekhmet: five variants, natural 5★, the first damage archetype. Zeus: five
  variants, natural 5★, Greek, the control archetype (a Thunderclap that stuns,
  freezes, sleeps, knocks back or provokes the whole enemy line). Neither
  Sekhmet nor Zeus has art in the bundle yet — the game shows letter plates and
  a grey dot until the files land, and keeps both out of the gacha.
- Models ship **canonical and decimated**: `tools/mesh.py anubis` reads the
  untouched export in `Art/Models/` and writes Y-up, metre, feet-on-origin,
  rest-equals-bind, four-influence files into `Pantheon/Resources/Models/`
  (2.7 MB for the family, was 154 MB), then re-skins them in numpy to prove it.
  The first export loaded as gold shards for five reasons listed in
  `Docs/PLAN.md`, all in the file. **Unconfirmed on device** since the fix; the
  first thing worth asking for is the `[ModelLibrary]` console block — the
  loader now prints the bounding box and skinner it built.
- The app opens on the island (`IslandView`): five landmarks over a painting
  that `tools/island.py` generated as a stand-in. The real painting wants a
  Gemini key.
- Portraits go through `BundleImage` (UIKit lookup). SwiftUI `Image("name")`
  drew nothing for loose bundle PNGs on device; never use it for one.
- The gacha pool is gated on shipped art (`UnitBlueprint.hasShippedArt`), so
  Sekhmet and Zeus are summonable the moment their portraits land and not
  before; the "Olympus Stirs" banner appears with Zeus's portraits too. The
  battle camera is solved for a portrait phone (`BattleSceneController`);
  `tools/appicon.py` drew the icon.
- Meshy is driven from here. `tools/meshy.py` took Sekhmet and then Zeus from
  a prompt to a rigged model with six clips for 53 credits each; the task ids
  are in `Art/Models/sekhmet.meshy.json` and `zeus.meshy.json`. The files could not be fetched, because
  `assets.meshy.ai` is not on the allow-list yet — see below.
- `tools/character.py` is the one place a rigged character is read (Blender
  USDZ or Meshy GLB), canonicalised, decimated, written and verified;
  `tools/mesh.py` runs a family through it, `tools/glb2usd.py` converts one
  file at full size. Nothing has been seen on a phone since the rewrite.
- Art for Anubis is done: 11 painted portraits, 5 stage backdrops, 2 summon
  banners, a particle sprite and a 10-texture UI kit. `tools/genart.py` makes
  more via Gemini when `GEMINI_API_KEY` is in the environment; it was not, last
  session. Sekhmet's portrait prompt is in `Docs/ART_2D.md`.
- Sound is 13 synthesised effects (`tools/sfx.py`) and two synthesised music
  loops (`tools/music.py`, island and battle), crossfaded by `AudioLibrary`.

### What this environment can reach

`api.meshy.ai` (with `MESHY_API_KEY` provisioned; task creation and polling
work), `generativelanguage.googleapis.com` (the Gemini host is open, but no key
was present), GitHub, and the package registries. **Not** `assets.meshy.ai` or
`cdn.meshy.ai`, where Meshy serves finished files and previews, nor
`docs.meshy.ai`. Tripo, Rodin, OpenAI and Hugging Face are also refused by the
environment's network policy with a 403 at CONNECT. Do not try to route around a
policy denial; report it.

To add a host: claude.ai/code → the cloud icon above the message box → hover
the environment → gear → **Network access: Custom** → list the domain →
**tick "Also include default list of common package managers"**. On Pro/Max,
**API credentials** in the same dialog is better for a keyed API: it opens the
host *and* keeps the key out of the session. Either way the change reaches
**new sessions only**.
