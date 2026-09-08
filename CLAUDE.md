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

## Where things stand

Read `Docs/PLAN.md` first. It has the measurements that decisions were based
on, the phase list, and an honest account of what this environment can and
cannot do. The short version:

- The game builds and runs on an iPhone. Battle, summon, collection, arena and
  campaign all work.
- Art is done for one character family: 11 painted portraits, 5 stage
  backdrops, 2 summon banners, a particle sprite and a 10-texture UI kit.
  `tools/genart.py` makes more via Gemini, which is reachable from here.
- Sound is 13 synthesised effects. `tools/sfx.py` regenerates them. No music.
- One 3D character, Anubis. `tools/mesh.py` decimates a Meshy export to a
  shippable triangle budget; its read-only path is tested, its decimating
  path is not yet run.
- Anubis's scale bug is fixed but **unconfirmed on device**. The first thing
  worth asking for is the `[ModelLibrary] 'anubis':` console line from a run.

### What this environment can reach

`generativelanguage.googleapis.com` (Gemini), GitHub, and the package
registries. Everything else — Meshy, Tripo, Rodin, OpenAI, Hugging Face — is
refused by the environment's network policy with a 403 at CONNECT. Do not try
to route around a policy denial; report it.

To add a host: claude.ai/code → the cloud icon above the message box → hover
the environment → gear → **Network access: Custom** → list the domain →
**tick "Also include default list of common package managers"**. On Pro/Max,
**API credentials** in the same dialog is better for a keyed API: it opens the
host *and* keeps the key out of the session. Either way the change reaches
**new sessions only**.
