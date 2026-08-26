# Pantheon

A Summoners War-style gacha RPG for iOS, built in SwiftUI and SceneKit, with real
3D characters. Greek to start — Zeus is fully built — with the roster designed
from the ground up to span Roman, Egyptian, Norse, Chinese, Japanese, Hindu,
Mesopotamian, Aztec, Celtic, Slavic, Yoruba and Polynesian mythology, and to
cover gods, demigods, heroes, titans, monsters, spirits and primordials.

This repository holds the complete game base: turn-based combat, the gacha, the
relic economy, PvE campaign, and PvP arena — all playable end to end today.

> The previous contents of this repo (the debt payoff scheduler) have moved to
> [`legacy/debt-payoff-scheduler/`](legacy/debt-payoff-scheduler/). Nothing was
> deleted.

---

## Running it

```bash
open Pantheon.xcodeproj
```

Select the **Pantheon** scheme, pick any iPhone simulator or a device, and run.
Xcode 16+, iOS 17+. No package dependencies, no CocoaPods, no build script.

```bash
xcodebuild -scheme Pantheon -destination 'platform=iOS Simulator,name=iPhone 15' test
```

If the project file ever gets mangled by a merge, `xcodegen generate` rebuilds it
from `project.yml`.

## It runs with zero art

This is the part worth knowing before you export anything. Every character that
has no model loads a **procedural placeholder rig** — correctly sized for its
archetype, tinted to its element, with the same attachment-point node names a
real rig exposes. It animates, takes hits, dies and gets summoned on a beam.

So combat pacing, camera work, VFX timing and every screen in the app are already
finished and testable. Dropping `zeus.usdz` into `Pantheon/Resources/Models/`
replaces the placeholder with no code change. **More → 3D assets** in the app
shows a green dot for every character that has a real model and a grey one for
every character still standing in.

## What you need to make

The full specification — scale, orientation, materials, rig node names, the
animation clip list, and the 3D AI Studio → Blender → Mixamo → USDZ route — is in
**[`Docs/ART_PIPELINE.md`](Docs/ART_PIPELINE.md)**. The short version, for Zeus:

| File | Folder |
|---|---|
| `zeus.usdz` — rigged, 2.05 m, Y-up, facing +Z, origin at the feet, animations embedded | `Pantheon/Resources/Models/` |
| `portrait_zeus.png` — 1024×1024 | `Pantheon/Resources/Portraits/` |
| `banner_olympus_rising.png` — 1284×800 | `Pantheon/Resources/Portraits/` |
| `spark.png` — 128×128 white radial glow | `Pantheon/Resources/Portraits/` |
| `olympus_peak.scn` + `olympus_peak_ibl.hdr` — optional | `Pantheon/Resources/Environments/` |

Animation clips the rig needs, by exact name: `idle`, `idle_combat`,
`attack_basic`, `attack_heavy`, `cast_loop`, `cast_release`, `ultimate`,
`hit_react`, `death`, `victory`, `summon_reveal`.

---

## What is built

**Combat.** Attack-bar turn order, five-element wheel, crits, glancing hits,
multi-hit skills, defence-ignore, 24 buffs and debuffs, shields, counterattacks,
revives, passive skills with triggers, and a full AI that scores every
(skill, target) pair. Fully deterministic from a seed, so battles replay exactly.

**Zeus.** Three active skills, an awakened passive, a leader skill, an evolution
path and an awakening cost:

- **Arc Lightning** — three strikes, each with a chance to Slow
- **Thunderbolt** — ignores 30% DEF, 70% Stun
- **Aegis of Olympus** — hits everything, scales with the debuffs on each target,
  50% Stun, and buffs the team's attack
- **Stormlord** *(awakened)* — a kill resets his cooldowns and buffs his attack
- **Leader** — +33% ATK to Greek allies

**Gacha.** Three scroll types with published rates, banner rate-ups, hard pity at
90, a soft-pity ramp from 67, the featured-unit guarantee, duplicates converting
to skill-ups, and a 3D summon reveal.

**Relics.** Six slots, 16 sets, main and sub stats, upgrade rolls to +15,
auto-equip scored per combat role, and set effects resolved inside the engine.

**Campaign.** Two chapters of Olympus, hand-authored and generated, with energy
costs, star ratings, first-clear rewards and gated progression.

**Arena.** Rank points with Elo-flavoured swings, six tiers with floors,
attack-attempt regeneration, a defence team the AI plays, and a defence simulator
that tells you how often your team actually holds.

**Progression.** Levelling, evolution to 6★, awakening with element essences,
skill-ups, and an economy of four currencies.

**Persistence.** Versioned, atomic, migrating saves. A corrupt file is quarantined
rather than deleted.

## Layout

```
Pantheon/
  App/           GameStore — the single source of truth — and the tab shell
  Core/
    Models/      Units, stats, skills, statuses, relics, the player
    Data/        UnitDatabase (Zeus + enemies), StageDatabase
    Battle/      The engine, damage maths, AI, seeded RNG, event stream
    Gacha/       Banners, rates, pity
    Progression/ Levelling, evolution, awakening, relic rolls
    PvE/         Campaign unlocks and rewards
    PvP/         Arena tiers, matchmaking, scoring
    Persistence/ Save file and new-game seeding
  Render/        SceneKit: model loading, placeholder rig, VFX, camera, playback
  UI/            SwiftUI screens
  Resources/     Where art goes
PantheonTests/   Engine determinism, progression maths, gacha rates, arena, saves
Docs/            ART_PIPELINE.md, DESIGN.md
```

The core is deliberately free of SwiftUI and SceneKit. The engine resolves a
whole turn the moment an action is submitted and hands back a list of events; the
renderer plays those back. That separation is why battles can be fast-forwarded,
skipped, simulated headlessly for arena defence scoring, and unit-tested.

`Docs/DESIGN.md` has the combat maths, the economy and the recipe for adding a
character or a whole new pantheon.

## What comes next

- More of Olympus: Hera, Poseidon, Hades, Athena, Ares, Artemis, Apollo
- The second pantheon — Egypt is the natural next one, and the leader-skill and
  campaign systems already scope by pantheon
- Server-authoritative arena. `ArenaService.pool(for:)` is the only seam that
  changes; battles are already deterministic and re-verifiable from a seed
- Guilds, a rune-farming dungeon loop, and a live-ops banner calendar
- Audio
