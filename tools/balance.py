#!/usr/bin/env python3
"""
Balance model for Pantheon.

There is no Swift toolchain in this environment (download.swift.org is blocked
by egress policy), so the Swift itself cannot be compiled or run here. What CAN
be checked is the thing that actually decides whether the game is any good: the
numbers.

This mirrors ONLY the tuning maths from Core — the stat curves, the damage
formula, the element wheel, the turn order and the gacha rates — using the same
constants that are hard-coded into the Swift. It is deliberately not a port of
the engine; it is the spreadsheet a designer would keep, made executable.

    python3 tools/balance.py            # full report
    python3 tools/balance.py --curve    # stat curves only
    python3 tools/balance.py --gacha    # summon odds and pity only

If a constant changes in Swift, change it here and re-run.
"""

import math, random, statistics, sys
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Constants — these must match Core/Progression/ProgressionService.swift and
# Core/Battle/DamageCalculator.swift exactly.
# ---------------------------------------------------------------------------

GRADE_STEP        = 1.35     # stat multiplier per star
LEVEL_STEP        = 0.075    # stat multiplier per level
DEF_CONSTANT      = 1000.0
DEF_WEIGHT        = 3.5
GLANCING_MULT     = 0.70
VARIANCE          = (0.95, 1.05)
ADVANTAGE_MULT    = 1.5
DISADVANTAGE_MULT = 0.7
ADVANTAGE_CRIT    = 0.15
ATB_RATE          = 0.07
MAX_TURNS         = 150

WHEEL_BEATS = {"ember": "gale", "gale": "tide", "tide": "ember"}

def matchup(att, dfn):
    if att == dfn: return "neutral"
    if WHEEL_BEATS.get(att) == dfn: return "advantage"
    if WHEEL_BEATS.get(dfn) == att: return "disadvantage"
    if {att, dfn} == {"radiance", "umbra"}: return "advantage"
    return "neutral"

def grade_mult(stars):  return GRADE_STEP ** (stars - 1)
def level_mult(level):  return 1 + LEVEL_STEP * (level - 1)
def max_level(stars):   return stars * 10 + 5

def mitigation(defense, ignore=0.0):
    eff = max(0.0, defense * (1 - ignore))
    return DEF_CONSTANT / (DEF_CONSTANT + eff * DEF_WEIGHT)

# ---------------------------------------------------------------------------
# Units
# ---------------------------------------------------------------------------

@dataclass
class Blueprint:
    id: str
    name: str
    element: str
    stars: int
    hp: float; atk: float; dfn: float; spd: float
    crit: float = 0.15
    critdmg: float = 0.50
    acc: float = 0.0
    res: float = 0.15
    skills: list = field(default_factory=list)   # (name, mult, hits, cd, defign, missbonus, aoe)

@dataclass
class Fighter:
    bp: Blueprint
    level: int
    stars: int
    relic_mult: float = 1.0      # crude stand-in for a relic loadout
    side: str = "player"
    hp: float = 0.0
    maxhp: float = 0.0
    atk: float = 0.0
    dfn: float = 0.0
    spd: float = 0.0
    crit: float = 0.15
    critdmg: float = 0.5
    atb: float = 0.0
    cds: list = field(default_factory=list)
    defbreak: int = 0

    def __post_init__(self):
        s = grade_mult(self.stars) * level_mult(self.level)
        self.maxhp = self.bp.hp * s * self.relic_mult
        self.hp = self.maxhp
        self.atk = self.bp.atk * s * self.relic_mult
        self.dfn = self.bp.dfn * s * self.relic_mult
        self.spd = self.bp.spd + (12 if self.relic_mult > 1.2 else 0)
        self.crit = min(1.0, self.bp.crit + (0.35 if self.relic_mult > 1.2 else 0))
        self.critdmg = self.bp.critdmg + (0.55 if self.relic_mult > 1.2 else 0)
        self.cds = [0] * len(self.bp.skills)

    @property
    def alive(self): return self.hp > 0

    def power(self):
        offense = self.atk * (1 + self.crit * self.critdmg)
        surviv  = self.maxhp * (1 + self.dfn / 1000)
        return int((offense * 1.6 + surviv * 0.22) * (self.spd / 100))

def resolve_hit(att, dfn, mult, defign, missbonus, rng):
    base = att.atk * mult
    if missbonus:
        base *= 1 + missbonus * (1 - dfn.hp / dfn.maxhp)
    d = dfn.dfn * (0.30 if dfn.defbreak > 0 else 1.0)
    base *= mitigation(d, defign)
    m = matchup(att.bp.element, dfn.bp.element)
    base *= {"advantage": ADVANTAGE_MULT, "neutral": 1.0, "disadvantage": DISADVANTAGE_MULT}[m]
    glancing = m == "disadvantage" and rng.random() < 0.15
    crit = (not glancing) and rng.random() < (att.crit + (ADVANTAGE_CRIT if m == "advantage" else 0))
    if crit:       base *= 1 + att.critdmg
    elif glancing: base *= GLANCING_MULT
    base *= rng.uniform(*VARIANCE)
    return max(1.0, base)

def simulate(team_a, team_b, seed=0):
    """One battle. Both sides use the highest-multiplier ready skill."""
    rng = random.Random(seed)
    for f in team_a: f.side = "a"
    for f in team_b: f.side = "b"
    all_f = team_a + team_b
    turns = 0
    while turns < MAX_TURNS:
        alive = [f for f in all_f if f.alive]
        if not [f for f in team_a if f.alive]: return "b", turns
        if not [f for f in team_b if f.alive]: return "a", turns
        step = min((1.0 - f.atb) / max(1e-6, f.spd * ATB_RATE) for f in alive)
        for f in alive: f.atb = min(1.0, f.atb + f.spd * ATB_RATE * step)
        actor = max((f for f in alive if f.atb >= 1 - 1e-9),
                    key=lambda f: (f.spd, -id(f)), default=None)
        if actor is None: continue
        actor.atb = 0.0
        turns += 1
        for i in range(len(actor.cds)):
            actor.cds[i] = max(0, actor.cds[i] - 1)
        if actor.defbreak > 0: actor.defbreak -= 1

        foes = [f for f in (team_b if actor.side == "a" else team_a) if f.alive]
        if not foes: continue
        ready = [i for i, s in enumerate(actor.bp.skills) if actor.cds[i] == 0]
        allies = [f for f in (team_a if actor.side == "a" else team_b) if f.alive]

        # Heal when someone actually needs it, damage otherwise. Without this the
        # model cannot see what a support kit is for.
        heal_idx = next((i for i in ready if actor.bp.skills[i][1] == 0.0), None)
        neediest = min((f.hp / f.maxhp for f in allies), default=1.0)
        if heal_idx is not None and neediest < 0.60:
            actor.cds[heal_idx] = actor.bp.skills[heal_idx][3]
            for f in allies:
                f.hp = min(f.maxhp, f.hp + f.maxhp * 0.25)
            continue

        dmg_ready = [i for i in ready if actor.bp.skills[i][1] > 0]
        if not dmg_ready: continue
        idx = max(dmg_ready, key=lambda i: actor.bp.skills[i][1] * actor.bp.skills[i][2])
        name, mult, hits, cd, defign, missbonus, aoe = actor.bp.skills[idx]
        actor.cds[idx] = cd
        targets = foes if aoe else [min(foes, key=lambda f: f.hp)]
        for _ in range(hits):
            for t in targets:
                if not t.alive: continue
                t.hp -= resolve_hit(actor, t, mult, defign, missbonus, rng)
                if "break" in name.lower(): t.defbreak = 2
    return "draw", turns

# ---------------------------------------------------------------------------
# The roster under test
# ---------------------------------------------------------------------------

ANUBIS = Blueprint("anubis_umbra", "Anubis (Dark)", "umbra", 4, hp=480, atk=27, dfn=28, spd=107,
    skills=[("Jackal's Due", 1.50, 2, 0, 0.0, 0.0, False),
            ("Weighing of the Heart", 4.10, 1, 3, 0.0, 1.10, False),
            ("Opening of the Mouth", 0.0, 0, 5, 0.0, 0.0, False)])

SHABTI    = Blueprint("shabti",    "Shabti",            "umbra",    2, 250, 25, 15,  96,
    skills=[("Grasp", 1.60, 1, 0, 0, 0, False)])
SERPOPARD = Blueprint("serpopard", "Serpopard",         "gale",     3, 300, 31, 17, 118,
    skills=[("Rake", 0.95, 2, 0, 0, 0, False), ("Pounce", 3.10, 1, 3, 0, 0, False)])
SCARAB    = Blueprint("scarab",    "Sun-Scarab Swarm",  "radiance", 3, 285, 30, 16, 112,
    skills=[("Swarm", 0.85, 3, 0, 0, 0, False)])
SENTINEL  = Blueprint("sentinel",  "Sandstone Sentinel","ember",    3, 500, 22, 36,  82,
    skills=[("Slab", 1.50, 1, 0, 0, 0, False), ("Quake", 2.20, 1, 3, 0, 0, True)])
AMMIT     = Blueprint("ammit",     "Ammit",             "umbra",    4, 530, 37, 27, 110,
    skills=[("Three Jaws", 0.90, 3, 0, 0, 0, False), ("Devour", 3.40, 1, 3, 0.25, 0.6, False)])
APEP      = Blueprint("apep",      "Apep",              "ember",    5, 980, 39, 31,  94,
    skills=[("Coil", 1.90, 1, 0, 0, 0, False), ("Chaos Break", 3.60, 1, 4, 0, 0, True)])

def mk(bp, level, stars, relic=1.0, boss=1.0):
    f = Fighter(bp, level, stars, relic)
    if boss != 1.0:
        f.maxhp *= boss; f.hp = f.maxhp; f.atk *= boss; f.dfn *= boss
    return f

STAGES = [
    # Enemy COUNT is the real difficulty dial, not enemy level: a lone unit
    # cannot win a three-on-one at any level, and four levelled units beat three
    # of almost anything. Each stage adds a body roughly when the player is
    # expected to have gained one, and levels rise monotonically so the board
    # reads honestly.
    #
    # The win rates come out near-binary because a team of five Anubis variants
    # is a mirror match with no stuns and no defence break. Once the roster has
    # other families in it there will be a real variance band; for now the
    # numbers below are gates, and they are meant to be.
    ("1-1 The First Gate",    400, [(SHABTI,5,2),(SHABTI,5,2)]),
    ("1-2 Reed Fields",       800, [(SHABTI,8,2),(SERPOPARD,8,3)]),
    ("1-3 Scarab Court",     1800, [(SERPOPARD,14,3),(SCARAB,14,3),(SHABTI,14,2)]),
    ("1-4 Hall of Sentinels",3600, [(SENTINEL,20,3),(SERPOPARD,20,3),(SCARAB,20,3),(AMMIT,20,4)]),
    ("1-5 Coils of Apep",    7000, [(SENTINEL,26,3),(SERPOPARD,26,3),(APEP,28,5,1.42),(AMMIT,26,4)]),
]

def build_stage(spec):
    out = []
    for e in spec:
        bp, lvl, st = e[0], e[1], e[2]
        boss = e[3] if len(e) > 3 else 1.0
        out.append(mk(bp, lvl, st, 1.0, boss))
    return out

def winrate(team_spec, stage_spec, trials=200):
    wins, lens = 0, []
    for s in range(trials):
        team = [mk(*t) for t in team_spec]
        foes = build_stage(stage_spec)
        r, turns = simulate(team, foes, seed=s)
        if r == "a": wins += 1
        lens.append(turns)
    return wins / trials, statistics.median(lens)

# ---------------------------------------------------------------------------
# Reports
# ---------------------------------------------------------------------------

def report_curve():
    print("\nANUBIS STAT CURVE")
    print(f"{'grade/level':>14}{'HP':>9}{'ATK':>7}{'DEF':>7}{'SPD':>6}{'power':>9}")
    for stars, lvl in [(4,1),(4,45),(5,1),(5,55),(6,1),(6,65)]:
        f = mk(ANUBIS, lvl, stars)
        print(f"{f'{stars}* lv{lvl}':>14}{f.maxhp:>9.0f}{f.atk:>7.0f}{f.dfn:>7.0f}{f.spd:>6.0f}{f.power():>9}")
    g = mk(ANUBIS, 55, 6, 1.60)
    print(f"{'6* lv55 geared':>14}{g.maxhp:>9.0f}{g.atk:>7.0f}{g.dfn:>7.0f}{g.spd:>6.0f}{g.power():>9}")

def report_elements():
    print("\nELEMENT WHEEL (must be a closed cycle plus a mirrored pair)")
    els = ["ember","tide","gale","radiance","umbra"]
    print("        " + "".join(f"{e[:4]:>10}" for e in els))
    for a in els:
        print(f"{a:>8}" + "".join(f"{matchup(a,b)[:4]:>10}" for b in els))

# What the player plausibly has in hand at each point in chapter one. A campaign
# tuned against arbitrary power tiers tells you nothing; tuned against this, the
# win rates are the actual difficulty curve.
# What the player plausibly has in hand at each point. The family is natural 4*,
# so a fresh account is a single 4* level 1 and the ladder runs through
# evolution to 5* and then 6*.
LADDERS = [
    ("1x 4* lv1 (day 1)", [(ANUBIS, 1, 4, 1.00)]),
    ("2x 4* lv15",        [(ANUBIS, 15, 4, 1.00)] * 2),
    ("3x 4* lv25",        [(ANUBIS, 25, 4, 1.05)] * 3),
    ("4x 4* lv35",        [(ANUBIS, 35, 4, 1.15)] * 4),
    ("4x 5* lv30 +relics",[(ANUBIS, 30, 5, 1.25)] * 4),
    ("4x 6* lv55 max",    [(ANUBIS, 55, 6, 1.60)] * 4),
]

def report_campaign(trials=200):
    print("\nCAMPAIGN — win rate over %d seeded battles" % trials)
    print("target: the intended team sits at 60-85%; the one below it should struggle\n")
    head = f"{'stage':>22}{'rec.pwr':>9}  "
    for name, _ in LADDERS: head += f"{name:>17}"
    print(head)
    for name, rec, spec in STAGES:
        row = f"{name:>22}{rec:>9}  "
        for _, team in LADDERS:
            wr, med = winrate(team, spec, trials=trials)
            row += f"{wr*100:>11.0f}% {med:>3.0f}t"
        print(row)
    print(f"\n{'team power':>22}{'':>9}  " + "".join(
        f"{sum(mk(*t).power() for t in team):>17,}" for _, team in LADDERS))

def report_gacha():
    print("\nSUMMON — 200,000 pulls on the featured banner")
    odds = {3: 0.790, 4: 0.180, 5: 0.030}
    assert abs(sum(odds.values()) - 1.0) < 1e-9, "published odds must sum to 1"
    hard, soft_start, soft_step = 90, 67, 0.06
    rng = random.Random(7)
    since, pulls, fives, gaps = 0, 200_000, 0, []
    for _ in range(pulls):
        since += 1
        r = rng.random()
        stars = 5 if r < odds[5] else (4 if r < odds[5] + odds[4] else 3)
        if since >= hard: stars = 5
        elif stars < 5 and since > soft_start and rng.random() < min(0.9, (since - soft_start) * soft_step):
            stars = 5
        if stars == 5:
            fives += 1; gaps.append(since); since = 0
    print(f"  published 5* rate      {odds[5]*100:.1f}%")
    print(f"  effective 5* rate      {fives/pulls*100:.2f}%  (pity included)")
    print(f"  mean pulls per 5*      {statistics.mean(gaps):.1f}")
    print(f"  median                 {statistics.median(gaps):.0f}")
    print(f"  90th percentile        {sorted(gaps)[int(len(gaps)*0.9)]}")
    print(f"  worst case seen        {max(gaps)}  (hard pity {hard})")
    scroll_cost = 100
    print(f"  divinity per 5* (mean) {statistics.mean(gaps)*scroll_cost:,.0f}")

def report_economy():
    print("\nECONOMY — first-clear income vs. upgrade costs")
    drachma = [700, 950, 1200, 1500, 3000]
    print(f"  chapter 1 full clear     {sum(drachma):,} drachma + 220 divinity")
    print(f"  one relic upgrade to +15 {sum(100*36 + l*100*36//3 for l in range(15)):,} drachma (6*)")
    print(f"  6* evolution ladder      {3000+8000+20000+60000+150000:,} drachma")
    print("  → chapter 1 alone funds roughly one relic. Grinding is the game.")

def report_tune(trials=140):
    """Search each stage's enemy level for the win rate it is supposed to have.

    Hand-iterating five stages against six ladders is slow and I get it wrong;
    stating the intended difficulty and solving for it is both faster and
    honest about what the curve is meant to be."""
    targets = [
        # stage index, which ladder it is tuned against, target win rate
        (0, 0, 0.97),   # tutorial: the day-one account clears it
        (1, 0, 0.60),   # solo, but only just — the "get a second unit" wall
        (2, 1, 0.80),   # two units, levelled
        (3, 2, 0.80),   # three units
        (4, 3, 0.80),   # the chapter boss: four units, no evolution required
    ]
    print("\nSTAGE TUNING — solving enemy level for the intended win rate")
    print(f"{'stage':>22}{'tuned against':>22}{'target':>8}{'level':>7}{'actual':>8}")
    for si, li, target in targets:
        name, rec, spec = STAGES[si]
        team = LADDERS[li][1]
        best = None
        for lvl in range(1, 46):
            probe = []
            for e in spec:
                probe.append((e[0], lvl, e[2]) + tuple(e[3:]))
            wr, _ = winrate(team, probe, trials=trials)
            if best is None or abs(wr - target) < abs(best[1] - target):
                best = (lvl, wr)
            if wr < target - 0.30 and lvl > 3:
                break
        flag = "" if abs(best[1] - target) < 0.12 else "   <- level alone cannot reach this; change the composition"
        print(f"{name:>22}{LADDERS[li][0]:>22}{target*100:>7.0f}%{best[0]:>7}{best[1]*100:>7.0f}%{flag}")

if __name__ == "__main__":
    a = sys.argv[1:]
    if "--tune" in a: report_tune()
    elif "--curve" in a: report_curve()
    elif "--gacha" in a: report_gacha()
    else:
        report_curve(); report_elements(); report_campaign(); report_gacha(); report_economy()
        print()
