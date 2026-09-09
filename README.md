# Pantheon

A Summoners War-style gacha RPG for iOS, landscape, in SwiftUI and SceneKit,
with real 3D characters. Eleven families are built — Egypt's Anubis, Sekhmet
and Thoth, Greece's Zeus, Ares, Heracles, Perseus, Hoplite, Satyr and Harpy:
fifty characters, each with a painted card and a rigged, animated model in a
stylised Summoners War look — plus the Shabti, the common tier that feeds them,
with the roster designed from the ground up to span Greek, Roman, Norse,
Chinese, Japanese, Hindu, Mesopotamian, Aztec, Celtic, Slavic, Yoruba and
Polynesian myth, and to cover gods, demigods, heroes, titans, monsters, spirits
and primordials.

This repository holds the complete base: turn-based combat, the gacha, the relic
economy, the PvE campaign and the PvP arena — playable end to end.

## Running it

```bash
open Pantheon.xcodeproj
```

Xcode 16+, iOS 17+. No package dependencies, no CocoaPods, no build script. If
the project file is ever mangled by a merge, `xcodegen generate` rebuilds it from
`project.yml`.

> **Read this before you build.** There is no Swift toolchain in the environment
> this was written in — `download.swift.org` is blocked by egress policy — so
> **none of this Swift has been compiled or run.** Expect a first-build session
> with some errors to clear. Two tools exist to keep that session short; see
> *Verifying* below, and `Docs/BALANCE.md` for exactly what is and is not checked.

## It runs with zero art

Every character without a model loads a **procedural placeholder rig** —
correctly sized for its archetype, tinted to its element, exposing the same
attachment-point node names a real rig does. It animates, takes hits, dies and
gets summoned on a beam. Combat pacing, camera work, VFX timing and every screen
are finished and testable before you export anything.

**More → 3D assets** in the app shows a green dot per character that has a real
model and a grey one for every character still standing in.

## What you need to make

One model. That is not a simplification — the five elemental Anubis are one mesh
tinted five ways, which is how the genre affords a roster of hundreds.

| File | Folder |
|---|---|
| `anubis.usdz` — rigged, 2.05 m, Y-up, facing +Z, origin at the feet | `Pantheon/Resources/Models/` |
| `portrait_anubis_<element>.png` — 1024×1024, recolours of one render are fine | `Pantheon/Resources/Portraits/` |
| `banner_duat_opens.png` — 1284×800 | same |
| `spark.png` — 128×128 white radial glow | same |

Or have the environment make it. Meshy is scriptable from Claude Code now, and
§0 of the pipeline doc is four commands from a prompt to the bundle; Sekhmet and
Zeus, the second and third families, were made that way.

**[`Docs/ART_PIPELINE.md`](Docs/ART_PIPELINE.md) has the Meshy prompt**, the
negative prompt, the settings, the five elemental colourways, the animation clip
contract and the six ways this goes wrong.
[`Docs/ART_2D.md`](Docs/ART_2D.md) has the image-generation prompts for the
portraits, stage backdrops, particle sprite and summon banner, with the exact
filenames the code looks up.
[`Docs/RESOURCES.md`](Docs/RESOURCES.md) documents every resource folder and the
flat-bundle naming rule that governs all of them.

## The character, and why it is this one

**Anubis, in five elements.** Fire, Water, Wind, Light and Dark, natural 4★,
sharing a kit shape and separated by stat lean, one changed effect per skill, and
leader skill.

- **Jackal's Due** — two strikes, each with a chance to Brand
- **Weighing of the Heart** — the judgement. Dark scales with the target's
  missing health; Fire burns; Water drains; Wind slows and knocks the attack bar
  back; Light strips two buffs
- **Opening of the Mouth** — revives a fallen ally, heals the team for 25%, and
  grants Attack Up / Recovery / Haste / Immunity depending on element
- **Scales of Ma'at** *(awakened)* — drops below half health once and sheds every
  debuff behind a shield
- **Leader** — ATK, HP, SPD, Resistance or CRIT Rate to Egyptian allies

Three reasons it is the right first character:

**It exercises the hardest path in the engine.** A revive forces dead-unit
targeting, state restoration and turn-order re-entry — the parts most likely to
be quietly broken. A kit that heals, strips, cleanses, shields, brands and
revives touches every field in the data model, so the next fifty gods are a
copy-edit rather than a design.

**A jackal head is the safest possible first 3D export.** Image-to-3D generators
are at their worst on human faces and hands. Here the animal head *is* the
silhouette, so the weakest part of the technology never appears, and an upright
humanoid body with a kilt rigs cleanly.

**It states the pitch on the first screen.** Opening with a Greek god reads as a
Greek game with others bolted on later. Opening with an Egyptian one reads as a
multi-mythology game, which is what this is. And Anubis is a major god without
being a king of gods, so Ra, Zeus, Odin and Amaterasu stay available as 5★ chase
units.

## What is built

**Combat.** Attack-bar turn order, a five-element wheel, crits, glancing hits,
multi-hit skills, defence-ignore, 24 buffs and debuffs, shields, counterattacks,
revives, passive skills with triggers, and an AI that scores every
(skill, target) pair. Deterministic from a seed, so battles replay exactly.

**Gacha.** Three scroll types with published rates, banner rate-ups, hard pity at
90, a soft-pity ramp from 67, the featured guarantee, duplicates converting to
skill-ups, and a 3D summon reveal.

**Relics.** Six slots, 16 sets, main and sub stats, upgrades to +15, auto-equip
scored per combat role, set effects resolved inside the engine. An inventory
with set tallies, filters, an efficiency dial against the role's ceiling,
bulk selling, locks, and reappraisal from +9; a picker per slot on the unit
sheet.

**The island.** The app opens on a painted hub with a landmark for every part
of the game; the ones with something to do glow. The campaign team stands
on the painting in its idle clips, sparks rise off the pool, a flame burns
at the obelisk, and the hour colours the painting. Tap the wallet for the
bazaar.

**Campaign.** Eight chapters — two of the Duat, three of Olympus, three of
Yggdrasil — hand-authored and generated, with energy, star ratings,
first-clear rewards and gated progression; later chapters field their
creatures at a higher grade on a measured curve. Any stage runs 1, 5, 10 or
20 times on auto with one loot panel at the end.

**The Halls of Essence.** One hall per element, five floors, a boss on every
floor, repeatable every day; the element essences and the relics worth
keeping come from here.

**The bazaar.** Scrolls, energy, relic packs, essences and a laurel exchange
for the game's own currencies, and a free offering every day. No real money.

**Arena.** Rank points with Elo-flavoured swings, six tiers with floors, attack
regeneration, an AI-played defence team, and a defence simulator that reports how
often your team actually holds.

**Progression.** Levelling, evolution to 6★, awakening with element essences,
skill-ups, four currencies.

**Persistence.** Versioned, atomic, migrating saves. A corrupt file is
quarantined rather than deleted.

**Sound.** Thirteen synthesised effects and two synthesised music loops, an
island loop and a battle loop, crossfaded as you move between screens.

## Verifying

No compiler, so two tools stand in for one.

```bash
python3 tools/swiftcheck.py --members --types   # 57 files, 74 structs, 325 functions
python3 tools/balance.py                # stat curves, campaign, gacha, economy
python3 tools/balance.py --tune         # solve enemy levels for a target win rate
```

`swiftcheck` catches the error classes that survive a rename and read perfectly
well on the page — memberwise-init and function-call argument order, unknown
argument labels, enum pattern arity, brace balance, and static members that no
longer exist. Each rule was proven by re-introducing a real bug and watching it
fail. It does **not** type-check.

`balance.py` mirrors the tuning maths and plays the campaign a few hundred times
per stage. It is the reason the numbers in `UnitDatabase` and `StageDatabase` are
what they are, and it found two things reading the design would not have: enemy
*count* is the difficulty dial rather than enemy level, and enemy *attack*
matters far more than enemy level. See `Docs/BALANCE.md`.

## Layout

```
Pantheon/
  App/           GameStore — the single source of truth — and the tab shell
  Core/
    Models/      Units, stats, skills, statuses, relics, the player
    Data/        UnitDatabase (the first four families + enemies), UnitDatabase+Roster (the seven newest), StageDatabase
    Battle/      Engine, damage maths, AI, seeded RNG, event stream
    Gacha/       Banners, rates, pity
    Progression/ Levelling, evolution, awakening, relic rolls
    PvE/ PvP/    Campaign unlocks and rewards; arena tiers and scoring
    Persistence/ Save file and new-game seeding
  Render/        SceneKit: model loading, placeholder rig, VFX, camera, playback
  UI/            SwiftUI screens
  Resources/     Where art goes
PantheonTests/   Engine determinism, progression maths, gacha rates, arena, saves
Docs/            PLAN.md (where this is going and why), ART_PIPELINE.md (the
                 Meshy prompt), ART_2D.md (image prompts), PLAYTEST.md (what to
                 check on device), RESOURCES.md, BALANCE.md, DESIGN.md
tools/           swiftcheck.py, balance.py
```

Core is free of SwiftUI and SceneKit. The engine resolves a whole turn the moment
an action is submitted and hands back a list of events; the renderer plays them
back. That is why battles can be fast-forwarded, skipped, simulated headlessly
for arena defence scoring, and unit-tested.

## What comes next

- See the landscape build on a phone: the battle framing, the Hall of Ka,
  the retextured models (`Docs/PLAYTEST.md`); GitHub builds and screenshots
  every push, the phone judges feel
- The living island, phase A: units idling on the painting, particles, a
  day-night cycle (`Docs/PLAN.md`, *The road to Summoners War*)
- A Greek campaign chapter. Zeus is live and leader skills already scope by
  pantheon; Olympus has no stages yet
- Arena tuning: nothing has checked whether its rating curve is sane
- Audio
