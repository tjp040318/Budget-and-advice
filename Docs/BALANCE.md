# Balance

There is no Swift toolchain in this environment — `download.swift.org` is
blocked by egress policy — so the Swift in this repo has never been compiled or
run. What *has* been checked is the part that decides whether the game is any
good: the numbers.

`tools/balance.py` mirrors the tuning maths from `Core` — the stat curves, the
damage formula, the element wheel, the ATB turn order and the gacha rates, using
the same constants that are hard-coded into the Swift. It is not a port of the
engine. It is the spreadsheet a designer would keep, made executable.

```bash
python3 tools/balance.py            # everything
python3 tools/balance.py --curve    # stat curves
python3 tools/balance.py --gacha    # summon odds and pity
python3 tools/balance.py --tune     # solve enemy levels for a target win rate
```

**If you change a constant in Swift, change it here and re-run.** The two are
kept in step by hand; nothing enforces it.

---

## The stat curve

Grade multiplies by 1.35 per star; level adds 7.5% linearly. Speed and the rate
stats do not scale at all, which is what lets a fast low-grade support stay
relevant next to a maxed god.

| Grade / level | HP | ATK | DEF | SPD | Power |
|---|---|---|---|---|---|
| 4★ lv1 (a fresh account) | 1,181 | 66 | 69 | 107 | 419 |
| 4★ lv45 (grade cap) | 5,078 | 286 | 296 | 107 | 2,075 |
| 5★ lv55 | 8,051 | 453 | 470 | 107 | 3,618 |
| 6★ lv65 | 12,484 | 702 | 728 | 107 | 6,370 |
| 6★ lv55 with relics | 17,391 | 978 | 1,014 | 119 | 12,012 |

## The campaign

Chapter 1 is tuned so each stage demands **exactly one more thing** than the one
before it, and enemy levels rise monotonically so the board reads honestly.

Win rate over 200 seeded battles per cell:

| Stage | 1× lv1 | 2× lv15 | 3× lv25 | 4× lv35 |
|---|---|---|---|---|
| 1-1 The First Gate | 100% | 100% | 100% | 100% |
| 1-2 Reed Fields | 23% | 100% | 100% | 100% |
| 1-3 Scarab Court | 0% | 100% | 100% | 100% |
| 1-4 Hall of Sentinels | 0% | 0% | 100% | 100% |
| 1-5 Coils of Apep | 0% | 0% | 0% | 100% |

Two things the model taught that reading the design would not have:

**Enemy count is the difficulty dial, not enemy level.** A lone unit cannot win
a three-on-one at *any* level — the tuner searched to level 45 and never got
above 14%. Four levelled units beat three of almost anything. Stages are
therefore built by adding a body, and level is only fine-tuning.

**Enemy ATK matters far more than enemy level.** A stage of Sandstone Sentinels
at level 45 is trivial because their attack is 22; the same stage with two
Ammits at level 26 is unwinnable. Composition, not numbers.

### Why the win rates are near-binary

Because a team of five Anubis variants is a mirror match: no stuns, no defence
break, the same stat curve on both sides, and every unit healing 25% of the team
every five turns. Damage-per-turn either exceeds the heal or it does not, and
there is almost no band in between.

That is an artefact of a one-family roster, not of the engine. Once there are
other families — different speeds, hard crowd control, defence breaks — a real
variance band appears. Do not over-tune against these numbers; re-run the model
when the second family lands.

## Summoning

| | |
|---|---|
| Published 5★ rate | 3.0% |
| Effective rate with pity | 3.39% |
| Mean pulls per 5★ | 29.5 |
| Median | 23 |
| 90th percentile | 70 |
| Worst case in 200,000 pulls | 78 (hard pity is 90) |

The hard pity at 90 is almost never what delivers — the soft-pity ramp from 67
gets there first. That is the intent: the guarantee is a floor under a bad run,
not the mechanism.

## Economy

A full chapter-1 clear pays 7,350 drachma and 220 divinity. Taking one 6★ relic
to +15 costs 180,000 drachma; the full 6★ evolution ladder costs 241,000. The
campaign funds roughly one relic. Everything after that is the grind, which is
the correct shape for the genre but worth stating plainly.

## What is not modelled

The arena, relic sub-stat roll distributions, and the awakening economy. The
arena in particular deserves the same treatment before it is tuned seriously —
`ArenaService.rateDefense` already simulates defence teams inside the game, but
nothing has checked whether its rating curve is sane.
