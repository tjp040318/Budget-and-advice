# Design reference

The rules the game runs on, in one place. Everything here is implemented — this
is a description of the code, not a proposal.

## Combat

Turn-based, up to 5 v 5 in the campaign and 4 v 4 in the arena.

**Turn order** is an attack bar. Everyone's bar fills at a rate proportional to
their Speed; whoever hits full acts. Acting resets the bar to zero. That makes
Speed the most contested stat in the game, and it makes attack-bar manipulation
(pushing an ally forward, knocking an enemy back) a real category of skill.

The engine advances time continuously rather than in fixed ticks — it computes
who reaches a full bar soonest and jumps there — so identical speeds resolve by
a stable tiebreak (higher speed, then side, then slot) instead of by float drift.

**Elements** form a hard cycle plus a mirrored pair:

```
Ember → Gale → Tide → Ember          Radiance ↔ Umbra
```

Attacking into an advantage: ×1.5 damage and +15% crit rate.
Attacking into a disadvantage: ×0.7 damage and a 15% chance of a glancing hit.

**Damage** is:

```
base       = scalingStat × multiplier
           × (1 + bonusPerDebuff × debuffCount)
           × (1 + bonusPerMissingHealth × missingHealth)
mitigation = 1000 / (1000 + effectiveDEF × 3.5)
damage     = base × mitigation × elementMod × critMod × setMods × random(0.95…1.05)
```

The defence curve is deliberately soft: doubling DEF does not halve damage, so
stacking defence is a choice rather than an obligation.

**Debuffs** roll twice — the skill's own chance, then a resistance check where
`resistance − accuracy` decides, with a 15% floor. Nothing is ever fully immune
by statistics alone; Immunity as a buff is how you actually stop a debuff.

**Determinism.** Every random decision goes through one seeded PRNG. The same
seed and the same inputs produce a byte-identical event stream. That is what
makes replays, arena defence simulation and regression tests possible, and it is
what a server will re-verify against when this goes online.

## Stats

Eight numbers: HP, ATK, DEF, SPD, CRIT Rate, CRIT DMG, Accuracy, Resistance.

HP, ATK and DEF scale with star grade (×1.35 per star) and level (+7.5% per
level, linear). **Speed does not scale at all** — a 3★ support with 110 base
speed outruns a maxed 6★ god with 100. That single decision is what keeps low
grade units in the game.

## Relics

Six slots. Odd slots have fixed flat main stats (ATK, DEF, HP); even slots roll
freely, which makes slots 2, 4 and 6 the actual build decision.

Sets come in two shapes. Two-piece sets grant a stat (Fury +35% ATK, Zephyr +25%
SPD). Four-piece sets grant an effect (Wrath: 22% chance of an extra turn; Styx:
35% lifesteal; Nemesis: attack bar from lost health). Sets stack — six Fury
pieces is three completions.

Percentages always apply to the **base** stat, never to relic flats. "+35% ATK"
therefore means the same thing on every build, which is what lets players compare
relics without a spreadsheet.

## Progression

| Path | Cost |
|---|---|
| Level | Feed fodder units for EXP. Cap is `stars × 10 + 5` |
| Evolve | Max level, plus `stars` fodder units at the same grade, plus drachma. Resets to level 1 |
| Awaken | Element essences. Grants a stat bonus and unlocks the passive skill |
| Skill up | Feed a duplicate of the same unit. Raises one random un-maxed skill |

## Summoning

| Scroll | 3★ | 4★ | 5★ |
|---|---|---|---|
| Mystical | 88.5% | 10% | 1.5% |
| Pantheon (banner) | 79% | 18% | 3% |
| Divine | — | 88% | 12% |

The banner carries pity: a guaranteed 4★+ every 15 pulls, a guaranteed 5★ at 90,
and a soft-pity ramp that starts at 67 and climbs steeply — so the hard cap is
rarely what actually delivers. A 5★ that is not the featured unit sets a flag
that makes the *next* 5★ guaranteed to be featured.

The rate table in the app shows the real numbers and the real pool, including
which units are at doubled weight.

## Arena

Rank points with an Elo-flavoured swing: beating someone above you pays more,
losing to someone below you costs more. Tier floors mean a bad night cannot undo
a season.

Defence teams are played by the same AI that plays campaign enemies, using the
same engine. The **Simulate defence** button runs your defence against five
generated attackers and reports how often it holds — so a defence is a measurable
choice rather than a guess.

Opponents are currently generated deterministically from your rating and the day.
When a backend lands, only `ArenaService.pool(for:)` changes; scoring, battle and
rewards are already the real ones.

## Elemental families

A character is not one unit, it is five. The Anubis family ships as Fire, Water,
Wind, Light and Dark: the same silhouette and the same *kit shape*, separated by

- **stat lean** — Fire trades health for attack, Water the reverse, Wind is the
  fastest of the five;
- **one changed effect per skill** — the judgement burns, or drains, or slows and
  knocks back the attack bar, or strips two buffs, or scales with missing health;
- **the team buff on the rite** — Attack Up, Recovery, Haste or Immunity;
- **the leader skill** — ATK, HP, SPD, Resistance or CRIT Rate.

They are five separate summonable units and five separate codex entries, and
they are **one 3D model**. Every variant points at `assetName: "anubis"` and
differs by `auraHex`, which tints the rim light, the aura, the ground ring and
the summon beam. That is how the genre affords hundreds of characters, and it
means a whole family costs one export.

`UnitDatabase.anubisVariant(_:)` builds all five from one `AnubisFlavour` table.
A second family is a second table.

## Adding a character

1. Add a family factory to `UnitDatabase` — or a single `UnitBlueprint` if it has
   no elemental variants. Stats are at 1★ level 1.
2. Add its ids to `UnitDatabase.summonPool` if it should be summonable.
3. Drop `<assetName>.usdz` and the portraits into `Resources/`.
4. Re-run `python3 tools/balance.py` and check the campaign table still has a
   shape.

## Adding a pantheon

1. Add a case to `Pantheon` with its realm name and accent colour, and put it in
   `Pantheon.live`.
2. Add characters with that pantheon.
3. Add a chapter in `StageDatabase` — hand-author it, or call
   `generatedChapter(...)` with a roster and a boss.

Leader skills already scope by pantheon, so "Greek allies gain 33% ATK" is one
line of data.

## Verifying a change

There is no Swift compiler in this environment, so two tools stand in:

```bash
python3 tools/swiftcheck.py --members   # argument order, unknown labels, dead references
python3 tools/balance.py                # stat curves, campaign win rates, gacha odds
```

`swiftcheck` catches the error classes that survive a rename and read fine on the
page: memberwise-init and function-call argument order, unknown argument labels,
enum pattern arity, and static members that no longer exist. It does not
type-check anything — see `Docs/BALANCE.md` for what is and is not verified.
