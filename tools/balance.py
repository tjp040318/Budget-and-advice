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
    python3 tools/balance.py --tower    # the Endless Tower's hundred floors
    python3 tools/balance.py --tiers    # the campaign's Hard and Hell against the ladders
    python3 tools/balance.py --raids    # the two raid bosses and their mechanics
    python3 tools/balance.py --relics   # quality odds, whetstone and gem ranges, the power-up bill
    python3 tools/balance.py --boons    # the nine boons' lift on five fights, and the socket's sources
    python3 tools/balance.py --events   # the event calendar: the week, the wheel, the multiplier matrix
    python3 tools/balance.py --regalia  # the eight regalia templates at I, III and V on two fights

If a constant changes in Swift, change it here and re-run.
"""

import itertools, math, random, re, statistics, sys
from dataclasses import dataclass, field, replace

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

# Relics — must match Core/Models/Relic.swift and Core/Progression/RelicService.swift.
# A drop's quality (Normal, Magic, Rare, Hero, Legend = 0-4 sub stats) by grade,
# in percent; the stones' ranges as a fraction of a 6* sub roll's base; the
# drachma each use costs.
QUALITY_NAMES   = ["Normal", "Magic", "Rare", "Hero", "Legend"]
QUALITY_WEIGHTS = {1: [45, 35, 15, 5, 0], 2: [45, 35, 15, 5, 0], 3: [30, 35, 22, 10, 3],
                   4: [18, 32, 28, 15, 7], 5: [10, 26, 32, 21, 11], 6: [6, 22, 34, 26, 12]}
SUB_STAT_BASE   = {"hp": 95, "atk": 7, "def": 7, "hp%": 0.03, "atk%": 0.03, "def%": 0.03,
                   "spd": 3, "crit": 0.025, "critdmg": 0.035, "acc": 0.03, "res": 0.03}
SUB_GRADE_SCALE = 0.22          # subStatBase: 1 + (grade - 1) * 0.22
STONE_RANGES    = {("whetstone", "rare"): (0.25, 0.45), ("whetstone", "hero"): (0.40, 0.65),
                   ("whetstone", "legend"): (0.60, 0.90), ("gem", "rare"): (0.85, 1.05),
                   ("gem", "hero"): (1.00, 1.25), ("gem", "legend"): (1.20, 1.50)}
STONE_COSTS     = {("whetstone", "rare"): 4_000, ("whetstone", "hero"): 9_000, ("whetstone", "legend"): 16_000,
                   ("gem", "rare"): 6_000, ("gem", "hero"): 14_000, ("gem", "legend"): 24_000}
POWER_UP_CHANCES = [1.0, 1.0, 1.0, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40]

# Boons — must match Core/Models/Boon.swift and Core/Progression/BoonService.swift.
# One CONDITIONAL line in the socket at the centre of the relic ring, read by
# the engine at one of four hooks; never a flat stat. Each family's size at 6*
# before the roll, and its hook; a Bane or a Ward is of one element.
BOONS = {  # family: (base at 6*, hook)              BoonFamily.base / .hook
    "bane":        (0.15, "damage"),       # +N% damage against <element>
    "giantSlayer": (0.18, "damage"),       # +N% damage against a boss
    "firstBlood":  (0.30, "damage"),       # +N% damage until this unit's first turn ends
    "lastStand":   (0.70, "damage"),       # +N% damage while under half health
    "executioner": (0.35, "damage"),       # +N% damage against a target under 30% health
    "ward":        (0.14, "damageTaken"),  # N% less damage from <element>
    "unfading":    (0.08, "turnStart"),    # heal N% of max health at the start of a turn begun under 50%
    "swiftFooted": (0.40, "battleStart"),  # +N attack bar when the battle begins
    "hydrasBlood": (0.05, "afterHit"),     # recover N% of the damage dealt
}
BOON_THRESHOLDS = {"lastStand": 0.50, "executioner": 0.30, "unfading": 0.50}   # BoonFamily.*Below
BOON_GRADE_SCALE = {4: 0.6, 5: 0.8, 6: 1.0}                                     # BoonService.gradeScale
BOON_ROLL = (0.75, 1.25)                                                        # BoonService.rollRange
BOON_PUSH = {"step": 0.08, "roll": (0.5, 1.5), "max": 5,                        # BoonService.pushStep / pushRollRange / maxPushes
             "aether": 4, "pure": 2, "drachma": {4: 8_000, 5: 16_000, 6: 30_000}}   # pushAether / pushPureAether / pushDrachma
BOON_SOURCES = {"Titan at S and better": (0.25, "6*"),                          # RaidGradeService.titanBoonChance / titanBoonGrade
                "Labyrinth B10": (0.10, "5*"),                                  # DungeonDatabase.labyrinthBoonChance / labyrinthBoonGrade
                "Tower F25 / F50 / F75 / F100": (1.0, "4* / 5* / 6* / 6*"),     # towerMilestoneReward
                "Judgment of the Realm on Hell": (1.0, "6*")}                   # TributeService.payout
# The enemies the engine calls a boss (Combatant.isBoss: a primordial, or
# anything three metres tall) — what Giant-slayer reads.
BOSS_IDS = {"apep", "boss_hydra", "boss_jotunn", "boss_colossus", "boss_unwrapped_king",
            "boss_bronze_colossus", "boss_longmen_dragon"}

# The Regalia — must match Core/Models/Regalia.swift and Core/Progression/RegaliaService.swift.
# ONE named item per family, unlocked by awakening, levelled I-V by duplicates
# fed past the skill-up cap; its passive is the kit's template. No RNG in it.
REGALIA = {  # template: the five magnitudes, level I first        RegaliaTemplate.magnitudes
    "keenEdge":        [0.04, 0.06, 0.08, 0.10, 0.12],   # striker: crit rate, flat
    "heavyHand":       [0.06, 0.09, 0.12, 0.15, 0.18],   # duelist: crit damage, flat
    "firstOffTheMark": [0.10, 0.15, 0.20, 0.25, 0.30],   # marksman: attack bar as the battle begins and as each wave walks on
    "unbowed":         [0.15, 0.20, 0.25, 0.30, 0.40],   # bruiser: +N% defence while under half health
    "bulwark":         [0.10, 0.15, 0.20, 0.25, 0.35],   # warden: the shields it casts are N% larger
    "wellspring":      [0.06, 0.09, 0.12, 0.15, 0.20],   # healer: the heals it casts are N% larger
    "lastingWord":     [0.05, 0.08, 0.10, 0.12, 0.15],   # oracle: accuracy, flat; debuffs held a turn longer from III
    "thiefOfTurns":    [0.15, 0.20, 0.25, 0.30, 0.40],   # trickster: attack-bar drains and gains N% larger
}
REGALIA_KITS = {"striker": "keenEdge", "duelist": "heavyHand", "marksman": "firstOffTheMark",   # RegaliaTemplate.template(for:)
                "bruiser": "unbowed", "warden": "bulwark", "healer": "wellspring",
                "oracle": "lastingWord", "trickster": "thiefOfTurns"}
REGALIA_RULES = {"levels": 5, "unbowedBelow": 0.5, "lastingWordFrom": 3}   # RegaliaTemplate.levels / unbowedBelow / lastingWordExtendsFrom
REGALIA_HANDWRITTEN = {  # UnitDatabase.handwrittenRegaliaTemplates
    "anubis": "lastingWord", "sekhmet": "heavyHand", "thoth": "wellspring", "shabti": "keenEdge",
    "zeus": "keenEdge", "ares": "thiefOfTurns", "heracles": "unbowed", "perseus": "firstOffTheMark",
    "hoplite": "bulwark", "satyr": "wellspring", "harpy": "thiefOfTurns",
}

def sub_stat_base(kind, grade=6):
    return SUB_STAT_BASE[kind] * (1 + (grade - 1) * SUB_GRADE_SCALE)

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

# Every fighter is numbered at birth, and a tie on speed goes to the earlier
# number: the engine's own tie-break is its combatant order. Breaking ties on
# `id(f)` — the object's address — made the sim's turn order differ from one
# process to the next, which is a report whose asserts can pass on Monday
# and fail on Tuesday (the boons' Swift-footed measured 5.4%, 6.2% and 7.3%
# on three runs of one seed).
_SEQ = itertools.count()

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
    burn: int = 0
    stun: int = 0
    # The socket: (family, element or None, magnitude), or None. `acted` is
    # First Blood's clock (Combatant.hasActed); `is_boss` what Giant-slayer
    # reads (Combatant.isBoss).
    boon: object = None
    acted: bool = False
    is_boss: bool = False
    seq: int = 0
    # The lineup's resonance, (kind, rank) or None, and the state its hooks
    # keep: a shield pool (the Legion), Attack Up turns (Valhalla), Recovery
    # turns and whether the Mandate has given them (the Mandate of Heaven).
    resonance: object = None
    shield: float = 0.0
    atk_up: int = 0
    regen: int = 0
    # The family's regalia, (template, magnitude, level) or None. `knock` is
    # the trickster's bar knock on its second skill, (delta, chance), and
    # `shield_cast` the warden's wall as a fraction of max health — both None
    # unless `--regalia` arms them, so no other report's fight moves.
    regalia: object = None
    knock: object = None
    shield_cast: object = None

    def __post_init__(self):
        self.seq = next(_SEQ)
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

def proc(name, keyword, default):
    """Chance of an on-hit effect, read off the skill's name: "(Burn)" means the
    default, "(Burn 35%)" means 35%. Keeps the sim's numbers next to the kit's."""
    m = re.search(keyword + r"\s*(\d+)%", name, re.IGNORECASE)
    return int(m.group(1)) / 100 if m else default

def boon_mult(att, dfn):
    """BattleEngine.boonDamageMultiplier: the attacker's boon on the way out
    and the defender's on the way in; 1 for a fight with none."""
    m = 1.0
    b = att.boon
    if b:
        fam, el, mag = b
        if fam == "bane" and dfn.bp.element == el: m *= 1 + mag
        elif fam == "giantSlayer" and dfn.is_boss: m *= 1 + mag
        elif fam == "firstBlood" and not att.acted: m *= 1 + mag
        elif fam == "lastStand" and att.hp / att.maxhp < BOON_THRESHOLDS["lastStand"]: m *= 1 + mag
        elif fam == "executioner" and dfn.hp / dfn.maxhp < BOON_THRESHOLDS["executioner"]: m *= 1 + mag
    w = dfn.boon
    if w and w[0] == "ward" and att.bp.element == w[1]:
        m *= max(0.0, 1 - w[2])
    return m

def boon_battle_start(fighters):
    """Swift-footed: a head start on the bar — BattleEngine.applyBattleStartEffects."""
    for f in fighters:
        if f.boon and f.boon[0] == "swiftFooted":
            f.atb = min(1.0, f.atb + f.boon[2])

def boon_turn_start(actor):
    """Unfading: the heal a turn begun under half health opens with
    (BattleEngine.applyTurnStartEffects). Returns what was healed."""
    b = actor.boon
    if not (b and b[0] == "unfading" and actor.alive and actor.hp / actor.maxhp < BOON_THRESHOLDS["unfading"]):
        return 0.0
    healed = min(actor.maxhp, actor.hp + actor.maxhp * b[2]) - actor.hp
    actor.hp += healed
    return healed

def boon_after_hit(actor, dealt):
    """Hydra's Blood: a share of the damage dealt comes back — BattleEngine.cast,
    after the hits, beside Styx. Returns what was healed."""
    b = actor.boon
    if not (b and b[0] == "hydrasBlood" and dealt > 0 and actor.alive):
        return 0.0
    healed = min(actor.maxhp, actor.hp + dealt * b[2]) - actor.hp
    actor.hp += healed
    return healed

def regalia_scale(f, template):
    """1 + the magnitude when the fighter's regalia is the template, else 1:
    BattleEngine.regaliaShieldScale / regaliaHealScale / regaliaBarScale."""
    r = f.regalia
    return 1 + r[1] if r and r[0] == template else 1.0

def regalia_def(f):
    """Unbowed: the bruiser's defence while under half health (DamageCalculator)."""
    r = f.regalia
    if r and r[0] == "unbowed" and f.hp / f.maxhp < REGALIA_RULES["unbowedBelow"]:
        return 1 + r[1]
    return 1.0

def regalia_hold(f):
    """A Lasting Word from level III: a debuff it lands holds a turn longer
    (BattleEngine.regaliaExtraTurns) — never a stun, which the sim keeps at one."""
    r = f.regalia
    return 1 if r and r[0] == "lastingWord" and r[2] >= REGALIA_RULES["lastingWordFrom"] else 0

def regalia_battle_start(fighters):
    """First Off the Mark: the marksman's head start on the bar, at the
    battle's start and as each wave walks on — BattleEngine.regaliaWaveStart."""
    for f in fighters:
        if f.alive and f.regalia and f.regalia[0] == "firstOffTheMark":
            f.atb = min(1.0, f.atb + f.regalia[1])

def apply_regalia(team, template, level):
    """A team wearing one template at a level: the two flat rate templates go
    on the stats (BattleEngine.buildSide); the rest are read at the hooks."""
    mag = REGALIA[template][level - 1]
    for f in team:
        f.regalia = (template, mag, level)
        if template == "keenEdge": f.crit = min(1.0, f.crit + mag)
        elif template == "heavyHand": f.critdmg += mag

# Pantheon resonance — Core/Models/Resonance.swift and
# Core/Progression/ResonanceService.swift, mirrored. A pair of one pantheon
# lights rank I, three or more rank II; four different pantheons the Concord.
# Applied to a mono team here (every member qualifies), which is the fight
# `--resonance` measures.
RESONANCE = {  # kind: (pantheon, rank I, rank II, rank II hook)      ResonanceService.bonuses / weighingDamage
    "weighingOfHearts": ("egyptian", {"dmg": 0.08}, {"dmg": 0.12}, "ka"),           # +N% damage against a debuffed enemy
    "olympianHubris":   ("greek",    {"critdmg": 0.10}, {"critdmg": 0.20}, "hubris"),
    "valhalla":         ("norse",    {"atk%": 0.05}, {"atk%": 0.08}, "valhalla"),
    "theLegion":        ("roman",    {"def%": 0.10}, {"def%": 0.15}, "legion"),
    "mandateOfHeaven":  ("chinese",  {"hp%": 0.08}, {"hp%": 0.12}, "mandate"),
    "concord":          (None, {"atk%": 0.06, "hp%": 0.06, "def%": 0.06, "acc": 0.05, "res": 0.05}, None, None),
}
RESONANCE_COUNTS = {"pair": 2, "majority": 3, "concord": 4}                 # ResonanceService.pairCount / majorityCount / concordPantheons
RESONANCE_HOOKS = {"ka": 0.15, "hubris": 0.25, "valhalla_turns": 1,          # kaHeal / hubrisBar / valhallaTurns
                   "legion": 0.20, "mandate_turns": 3, "below": 0.5}         # legionShield / mandateTurns / lowHealthBelow
ATTACK_UP_MULT = 1.50    # StatusKind.multiplier(for: .atkPercent) under Attack Up
RECOVERY_HEAL = 0.15     # BattleEngine.applyTurnStartEffects: Recovery regenerates 15% of max

def resonance_mult(att, dfn):
    """BattleEngine.resonanceDamageMultiplier, and Attack Up: the Weighing of
    Hearts against a judged — debuffed — enemy; Valhalla's fury after a fall."""
    m = 1.0
    r = att.resonance
    if r and r[0] == "weighingOfHearts" and (dfn.defbreak > 0 or dfn.burn > 0 or dfn.stun > 0):
        m *= 1 + RESONANCE["weighingOfHearts"][r[1]]["dmg"]
    if att.atk_up > 0:
        m *= ATTACK_UP_MULT
    return m

def land(t, dmg):
    """Damage into a fighter, its shield first (BattleEngine.applyDamage).
    Returns what reached the health."""
    if t.shield > 0:
        absorbed = min(t.shield, dmg)
        t.shield -= absorbed
        dmg -= absorbed
    applied = min(max(0.0, t.hp), dmg)
    t.hp -= dmg
    return applied

def apply_resonance(team, kind, rank):
    """A mono team of the kind's pantheon at a rank: the stat bonuses in a
    leader skill's terms (BattleEngine.buildSide), the hooks armed."""
    _, one, two, _ = RESONANCE[kind]
    bonuses = one if rank == 1 else (two or one)
    for f in team:
        f.resonance = (kind, rank)
        f.maxhp *= 1 + bonuses.get("hp%", 0.0); f.hp = f.maxhp
        f.atk *= 1 + bonuses.get("atk%", 0.0)
        f.dfn *= 1 + bonuses.get("def%", 0.0)
        f.critdmg += bonuses.get("critdmg", 0.0)

def resolve_hit(att, dfn, mult, defign, missbonus, rng, sure=False):
    """`sure` is a skill that always crits — "(Crit)" in its name."""
    base = att.atk * mult
    if missbonus:
        base *= 1 + missbonus * (1 - dfn.hp / dfn.maxhp)
    d = dfn.dfn * (0.30 if dfn.defbreak > 0 else 1.0) * regalia_def(dfn)
    base *= mitigation(d, defign)
    m = matchup(att.bp.element, dfn.bp.element)
    base *= {"advantage": ADVANTAGE_MULT, "neutral": 1.0, "disadvantage": DISADVANTAGE_MULT}[m]
    glancing = m == "disadvantage" and rng.random() < 0.15
    crit = sure or ((not glancing) and rng.random() < (att.crit + (ADVANTAGE_CRIT if m == "advantage" else 0)))
    if crit:       base *= 1 + att.critdmg
    elif glancing: base *= GLANCING_MULT
    base *= rng.uniform(*VARIANCE)
    base *= boon_mult(att, dfn)
    base *= resonance_mult(att, dfn)
    return max(1.0, base)

def simulate(team_a, team_b, seed=0, stats=None, first_wave=True):
    """One battle. Both sides use the highest-multiplier ready skill.

    `stats`, when given, collects each side's damage dealt, taken and healed
    (`stats["dealt"]["a"]` …), which is what `--boons` measures. `first_wave`
    is false for the later waves of a run, whose fighters already had their
    battle start (Swift-footed fires once a run, like the engine's)."""
    rng = random.Random(seed)
    for f in team_a: f.side = "a"
    for f in team_b: f.side = "b"
    all_f = team_a + team_b
    ka_spent, mandate_spent, legion_spent = set(), set(), set()
    def note(key, side, amount):
        if stats is not None and amount:
            bucket = stats.setdefault(key, {})
            bucket[side] = bucket.get(side, 0.0) + amount
    def allies_of(f):
        return [x for x in (team_a if f.side == "a" else team_b) if x.alive and x is not f]
    def fell(f):
        """BattleEngine.resonanceOnFall: Valhalla's fury for the Norse who
        remain, the Weighing's Ka once a side."""
        r = f.resonance
        if not r or r[1] < 2: return
        if r[0] == "valhalla":
            for x in allies_of(f): x.atk_up = RESONANCE_HOOKS["valhalla_turns"]
        if r[0] == "weighingOfHearts" and f.side not in ka_spent:
            ka_spent.add(f.side)
            for x in allies_of(f):
                healed = min(x.maxhp, x.hp + x.maxhp * RESONANCE_HOOKS["ka"]) - x.hp
                x.hp += healed
                note("healed", x.side, healed); note("boonHealed", x.side, healed)
    def end_turn(actor):
        """The turn ends: First Blood's clock, and Attack Up ticks down the
        way a status does at the end of its holder's turn."""
        actor.acted = True
        if actor.atk_up > 0: actor.atk_up -= 1
    if first_wave:
        boon_battle_start(all_f)
    # First Off the Mark fires against every wave, not the first alone
    # (BattleEngine.regaliaWaveStart).
    regalia_battle_start(all_f)
    turns = 0
    while turns < MAX_TURNS:
        alive = [f for f in all_f if f.alive]
        if not [f for f in team_a if f.alive]: return "b", turns
        if not [f for f in team_b if f.alive]: return "a", turns
        step = min((1.0 - f.atb) / max(1e-6, f.spd * ATB_RATE) for f in alive)
        for f in alive: f.atb = min(1.0, f.atb + f.spd * ATB_RATE * step)
        actor = max((f for f in alive if f.atb >= 1 - 1e-9),
                    key=lambda f: (f.spd, -f.seq), default=None)
        if actor is None: continue
        actor.atb = 0.0
        turns += 1
        # Each side's own actions, for the tempo readings (`--regalia`): a
        # head start or a knock buys actions, which a per-turn figure hides.
        note("turns", actor.side, 1)
        for i in range(len(actor.cds)):
            actor.cds[i] = max(0, actor.cds[i] - 1)
        if actor.defbreak > 0: actor.defbreak -= 1
        # Burn ticks at the start of the burning unit's turn for a flat 5% of
        # max HP, ignoring defence — BattleEngine.swift, "Burn ticks for a
        # flat share of max HP". Two turns per application.
        if actor.burn > 0:
            note("taken", actor.side, min(max(0.0, actor.hp), actor.maxhp * 0.05))
            actor.hp -= actor.maxhp * 0.05
            actor.burn -= 1
            if not actor.alive:
                fell(actor)
                continue
        # Recovery regenerates (the Mandate's, here), then Unfading: a turn
        # begun under half health opens with a heal —
        # BattleEngine.applyTurnStartEffects, before the stun is checked.
        if actor.regen > 0:
            healed = min(actor.maxhp, actor.hp + actor.maxhp * RECOVERY_HEAL) - actor.hp
            actor.hp += healed
            actor.regen -= 1
            note("healed", actor.side, healed); note("boonHealed", actor.side, healed)
        opened = boon_turn_start(actor)
        note("healed", actor.side, opened); note("boonHealed", actor.side, opened)
        # Hard control consumes the turn: BattleEngine skips a stunned, frozen
        # or sleeping unit's action and ticks the status down. The turn still
        # ENDS, which is what First Blood's clock reads.
        if actor.stun > 0:
            actor.stun -= 1
            end_turn(actor)
            continue

        foes = [f for f in (team_b if actor.side == "a" else team_a) if f.alive]
        if not foes: continue
        ready = [i for i, s in enumerate(actor.bp.skills) if actor.cds[i] == 0]
        allies = [f for f in (team_a if actor.side == "a" else team_b) if f.alive]

        # A skill of no damage named for a break — the umbra oracle's and
        # trickster's "Line Break (Def Break 60%)" — is a line-wide break,
        # cast when a foe stands unbroken; it was read as a heal before
        # 2026-09-17, which is what left the oracle's regalia unmeasurable.
        break_idx = next((i for i in ready if actor.bp.skills[i][1] == 0.0 and "break" in actor.bp.skills[i][0].lower()), None)
        if break_idx is not None and any(f.defbreak == 0 for f in foes):
            bname = actor.bp.skills[break_idx][0]
            actor.cds[break_idx] = actor.bp.skills[break_idx][3]
            for t in foes:
                if rng.random() < proc(bname, "def break", 0.60): t.defbreak = 2 + regalia_hold(actor)
            end_turn(actor)
            continue
        # Heal when someone actually needs it, damage otherwise. Without this the
        # model cannot see what a support kit is for.
        heal_idx = next((i for i in ready if actor.bp.skills[i][1] == 0.0 and "break" not in actor.bp.skills[i][0].lower()), None)
        neediest = min((f.hp / f.maxhp for f in allies), default=1.0)
        if heal_idx is not None and neediest < 0.60:
            actor.cds[heal_idx] = actor.bp.skills[heal_idx][3]
            if actor.shield_cast:
                # A warden's wall (`--regalia` arms it): every ally shielded
                # for a share of max health, a Bulwark's larger —
                # BattleEngine.applyStatus, the shield magnitude.
                for f in allies:
                    f.shield = max(f.shield, f.maxhp * actor.shield_cast * regalia_scale(actor, "bulwark"))
            else:
                # A Wellspring's heals are larger — BattleEngine.applyUtility.
                # What the item itself gave back over the plain heal is noted
                # apart, the way a boon's own healing is.
                scale = regalia_scale(actor, "wellspring")
                for f in allies:
                    plain = min(f.maxhp, f.hp + f.maxhp * 0.25) - f.hp
                    healed = min(f.maxhp, f.hp + f.maxhp * 0.25 * scale) - f.hp
                    f.hp += healed
                    note("healed", actor.side, healed)
                    note("boonHealed", actor.side, healed - plain)
            end_turn(actor)
            continue

        dmg_ready = [i for i in ready if actor.bp.skills[i][1] > 0]
        if not dmg_ready:
            end_turn(actor)
            continue
        # An AoE is worth its multiplier times the bodies it hits, which is
        # how AIController values it too; without this no ultimate that hits
        # the line for less than the basic's total would ever be cast.
        idx = max(dmg_ready, key=lambda i: actor.bp.skills[i][1] * actor.bp.skills[i][2]
                  * (len(foes) if actor.bp.skills[i][6] else 1))
        name, mult, hits, cd, defign, missbonus, aoe = actor.bp.skills[idx]
        actor.cds[idx] = cd
        targets = foes if aoe else [min(foes, key=lambda f: f.hp)]
        dealt = 0.0
        for _ in range(hits):
            for t in targets:
                if not t.alive: continue
                dmg = resolve_hit(actor, t, mult, defign, missbonus, rng, sure="(crit)" in name.lower())
                applied = land(t, dmg)
                dealt += applied
                note("dealt", actor.side, applied)
                note("taken", t.side, applied)
                # A Lasting Word holds a break or a burn a turn longer; a stun never.
                if "break" in name.lower(): t.defbreak = 2 + regalia_hold(actor)
                if "burn" in name.lower() and rng.random() < proc(name, "burn", 0.30): t.burn = 2 + regalia_hold(actor)
                if "stun" in name.lower() and rng.random() < proc(name, "stun", 0.55): t.stun = 1
                if not t.alive:
                    fell(t)
                    # Olympian Hubris: a Greek kill feeds the killer's bar.
                    r = actor.resonance
                    if r and r[0] == "olympianHubris" and r[1] >= 2:
                        actor.atb = min(1.0, actor.atb + RESONANCE_HOOKS["hubris"])
                elif t.resonance and t.resonance[1] >= 2 and t.hp / t.maxhp < RESONANCE_HOOKS["below"]:
                    # BattleEngine.resonanceOnLowHealth, once a side each: the
                    # Mandate's Recovery for the first to fall under half, the
                    # Legion's shield for the first Roman.
                    if t.resonance[0] == "mandateOfHeaven" and t.side not in mandate_spent:
                        mandate_spent.add(t.side)
                        t.regen = RESONANCE_HOOKS["mandate_turns"]
                    elif t.resonance[0] == "theLegion" and t.side not in legion_spent:
                        legion_spent.add(t.side)
                        t.shield = t.maxhp * RESONANCE_HOOKS["legion"]
        # The trickster's bar knock on its second skill (`--regalia` arms it),
        # a Thief of Turns' larger — BattleEngine.applyUtility, attackBarChange.
        if actor.knock and idx == 1:
            delta, chance = actor.knock
            for t in targets:
                if t.alive and rng.random() < chance:
                    t.atb = max(0.0, t.atb - delta * regalia_scale(actor, "thiefOfTurns"))
        # Hydra's Blood, after the hits; and the turn ends.
        drunk = boon_after_hit(actor, dealt)
        note("healed", actor.side, drunk); note("boonHealed", actor.side, drunk)
        end_turn(actor)
    return "draw", turns

# ---------------------------------------------------------------------------
# The roster under test
# ---------------------------------------------------------------------------

# THE LIGHT AND DARK PREMIUM — UnitDatabase.lightDarkPremium, mirrored. Since
# 2026-09-17 a Radiance or Umbra form of a ROSTER family carries x1.08 on its
# attack, health and defence over the family's numbers (the owner: "PREMIUM
# PREMIUM mons that need to be better than the rest"), and is drawn by the
# Light & Dark scroll alone. The Swift applies it once, to every roster
# blueprint on its way into the registry; here `premium` is that step and
# `form` builds one elemental form of a family through it.
#
# WHERE the sim applies it: only where it mirrors a SPECIFIC shipped light or
# dark blueprint — an enemy roster that names one (the Tower's Sand Stair
# Horus, the Weighing Floor's Sekhmet and Shabti, the Coil's Anubis:
# ANUBIS_DARK, SHABTI3_DARK, `form`) and the variants report, which measures
# the shipped forms. The reference blueprints (ANUBIS, SHABTI3, SEKHMET ...)
# hold the FAMILY's numbers and stand for all five forms; the benchmark and
# every stand-in team (the ladders, the boons' "four maxed 6*", the raids'
# "a unit on each element the boss opens to", the arena's four-colour line)
# stay on them, because a calibrated band is an instrument and a team of
# four premium copies is a team nobody fields — with the premium on the
# stand-ins, Hydra's Blood read 20.3% (band 6-18) and Olympian Hubris I 2.8%
# (band 3-8) the day it landed, on fights no design had changed. Enemies
# (E_*, the bosses, the campaign's shabti, scarab and ammit) never pass
# through it: a campaign wave's Radiance unit is an enemy blueprint of its
# own in the Swift too. `--variants` measures what the premium buys.
LIGHT_DARK_PREMIUM = 1.08
LIGHT_DARK = ("radiance", "umbra")

def premium(bp):
    """The registered form of a roster blueprint: the family's numbers, or
    those numbers lifted for a Radiance or Umbra form (UnitDatabase.withLightDarkPremium)."""
    if bp.element not in LIGHT_DARK:
        return bp
    return replace(bp, hp=bp.hp * LIGHT_DARK_PREMIUM, atk=bp.atk * LIGHT_DARK_PREMIUM,
                   dfn=bp.dfn * LIGHT_DARK_PREMIUM)

def form(bp, element, **changes):
    """One SHIPPED elemental form of a roster family from its reference
    blueprint, premium included where the element earns it — for a site that
    mirrors a blueprint the game names, or the sim's Horus of the Sand Stair
    fights on numbers the game's does not. A stand-in uses `replace`."""
    return premium(replace(bp, element=element, **changes))

# The family's numbers (the dark form is the archetype the others are within
# a few points of): the benchmark every report fights, and the stand-in.
ANUBIS = Blueprint("anubis_umbra", "Anubis (Dark)", "umbra", 4, hp=480, atk=27, dfn=28, spd=107,
    skills=[("Jackal's Due", 1.50, 2, 0, 0.0, 0.0, False),
            ("Weighing of the Heart", 4.10, 1, 3, 0.0, 1.10, False),
            ("Opening of the Mouth", 0.0, 0, 5, 0.0, 0.0, False)])
# The SHIPPED dark Anubis, premium on, for the one roster that names him as
# an enemy (the Tower's Coil).
ANUBIS_DARK = premium(ANUBIS)

SHABTI    = Blueprint("shabti",    "Shabti",            "umbra",    2, 250, 25, 15,  96,
    skills=[("Grasp", 1.60, 1, 0, 0, 0, False)])
# The summonable Shabti family: the gacha's 3* tier and the training hall's
# fodder. A two-skill servant a grade under Anubis; the Umbra one is the
# archetype and the other four are within ten percent of it.
SHABTI3   = Blueprint("shabti_umbra", "Shabti (Dark)",   "umbra",    3, 300, 25, 20,  98,
    skills=[("Clay Grasp", 1.60, 1, 0, 0, 0, False), ("Answer the Call", 2.30, 1, 3, 0, 0, False)])
SHABTI3_DARK = premium(SHABTI3)      # the shipped dark Shabti, where a roster names it (the Weighing Floor)
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

# The second family. Natural 5*, attacker: two-hit claws, a single-target nuke
# that breaks defence (the sim keys defence break off the word "break"), and an
# AoE ultimate. The Ember variant is the archetype; the other four are within a
# few points of it.
SEKHMET = Blueprint("sekhmet_ember", "Sekhmet (Fire)", "ember", 5, hp=410, atk=38, dfn=23, spd=106,
    skills=[("Rake of the Lioness (Burn)", 1.50, 2, 0, 0.0, 0.0, False),
            ("Eye of Ra (Def Break)", 4.80, 1, 3, 0.0, 0.0, False),
            ("Wrath of the Eye", 2.60, 1, 5, 0.0, 0.0, True)])

# The third family and the first Greek. Natural 5*, controller: one big bolt,
# an AoE Thunderclap whose stun the sim keys off the word "stun" (one turn,
# per target, at the chance in the name), and a single-target Keraunos that
# ignores 40% of defence. The Ember variant is the archetype; the other four
# trade a little attack for health and fight with second and third skills of
# their own (HANDWRITTEN_VARIANTS, below).
ZEUS = Blueprint("zeus_ember", "Zeus (Fire)", "ember", 5, hp=445, atk=36, dfn=25, spd=105, acc=0.10,
    skills=[("Thunderbolt (Burn 35%)", 3.10, 1, 0, 0.0, 0.0, False),
            ("Thunderclap (Stun 55%)", 2.00, 1, 4, 0.0, 0.0, True),
            ("Keraunos", 5.00, 1, 5, 0.40, 0.0, False)])

# The second roster. Kits as in Pantheon/Core/Data/UnitDatabase+Roster.swift;
# the sim reads burn and stun off the skill names and nothing else, so a
# provoke, a heal or a shield shows up here only as the damage it does not do.
# Each is the FIRE form; the second and third skills are the element's own
# now, so the fire form's are what these carry, and the other four forms are
# in HANDWRITTEN_VARIANTS below.
ARES = Blueprint("ares_ember", "Ares (Fire)", "ember", 5, hp=420, atk=40, dfn=22, spd=104, crit=0.20,
    skills=[("Sword of War (Burn 30%)", 3.00, 1, 0, 0.0, 0.0, False),
            ("War Frenzy", 0.0, 0, 3, 0.0, 0.0, False),
            ("Slaughter", 4.60, 1, 4, 0.0, 0.80, False)])
HERACLES = Blueprint("heracles_ember", "Heracles (Fire)", "ember", 4, hp=560, atk=26, dfn=30, spd=98,
    skills=[("Club Swing (Burn 30%)", 2.90, 1, 0, 0.0, 0.0, False),
            ("Nemean Roar", 1.60, 1, 4, 0.0, 0.0, True),
            ("Twelve Labours", 0.30 * 560 / 26, 1, 4, 0.30, 0.0, False)])   # 30% of max HP, as attack multiples
PERSEUS = Blueprint("perseus_ember", "Perseus (Fire)", "ember", 4, hp=470, atk=31, dfn=24, spd=110, acc=0.10,
    skills=[("Harpe Cuts (Burn 25%)", 1.45, 2, 0, 0.0, 0.0, False),
            ("Bronze Blade (Burn 50%)", 1.80, 2, 3, 0.25, 0.0, False),
            ("Gorgon's Blood (Burn 60%)", 2.20, 1, 5, 0.0, 0.0, True)])
THOTH = Blueprint("thoth_ember", "Thoth (Fire)", "ember", 5, hp=520, atk=26, dfn=30, spd=108, acc=0.15, res=0.20,
    skills=[("Reed Stroke (Burn 35%)", 2.60, 1, 0, 0.0, 0.0, False),
            ("Words of Fire", 0.0, 0, 4, 0.0, 0.0, False),
            ("Decree of Djehuty", 0.0, 0, 5, 0.0, 0.0, False)])
HOPLITE = Blueprint("hoplite_ember", "Hoplite (Fire)", "ember", 3, hp=340, atk=22, dfn=26, spd=96,
    skills=[("Spear Jab (Burn 25%)", 1.70, 1, 0, 0.0, 0.0, False), ("Spartan Thrust (Burn 60%)", 2.40, 1, 3, 0.0, 0.0, False)])
SATYR = Blueprint("satyr_ember", "Satyr (Fire)", "ember", 3, hp=300, atk=22, dfn=20, spd=104,
    skills=[("Hoof Kick (Burn 25%)", 1.70, 1, 0, 0.0, 0.0, False), ("Bonfire Reel", 0.0, 0, 4, 0.0, 0.0, False)])
HARPY = Blueprint("harpy_ember", "Harpy (Fire)", "ember", 3, hp=270, atk=28, dfn=16, spd=112,
    skills=[("Talon Rake (Burn 25%)", 1.00, 2, 0, 0.0, 0.0, False), ("Cinder Dive (Burn 60%)", 2.50, 1, 3, 0.0, 0.0, False)])

# The hand-written families' second and third skills, one pair per element:
# the `switch element` in each variant builder of UnitDatabase.swift and
# UnitDatabase+Roster.swift, mirrored here in the sim's own terms exactly as
# ELEMENT_SKILLS mirrors the table families. Freeze and Sleep are a stun, a
# max-health blow is ("hp", fraction) and is resolved against the family's
# numbers, a rite with no damage is a 0.0 (the sim heals on it), and a 3*
# family has one skill per element. One element per family is its home and
# keeps the skills as first written: dark for Anubis and the Shabti, fire for
# Sekhmet, Zeus, Ares and Heracles, light for Perseus, water for Thoth, the
# Hoplite and the Harpy, wind for the Satyr. The reference blueprint of each
# family above is ONE of these forms and must agree with its row here; the
# check under the table refuses to run the file when they drift.
HANDWRITTEN_VARIANTS = {
    "anubis": {
        "ember":    [("Verdict of Ash (Burn 70%)", 3.70, 1, 3, 0.30, 0, False), ("Rite of the Ash Road", 0.0, 0, 5, 0, 0, False)],
        "tide":     [("Ferryman's Toll (Stun 60%)", 3.50, 1, 3, 0, 0, False), ("Rite of the Reed Sea", 0.0, 0, 5, 0, 0, False)],
        "gale":     [("Khamsin Lash", 1.40, 3, 3, 0, 0, False), ("Breath of the Khamsin", 0.0, 0, 5, 0, 0, False)],
        "radiance": [("Solar Verdict (Crit)", 3.20, 1, 3, 0, 0, False), ("Rite of the Night Sun", 0.0, 0, 5, 0, 0, False)],
        "umbra":    [("Weighing of the Heart", 4.10, 1, 3, 0.0, 1.10, False), ("Opening of the Mouth", 0.0, 0, 5, 0.0, 0.0, False)],
    },
    "shabti": {
        "ember":    [("Kiln Fire (Burn 60%)", 2.20, 1, 3, 0, 0, False)],
        "tide":     [("Nile Undertow (Stun 50%)", 2.30, 1, 3, 0, 0, False)],
        "gale":     [("Dust Devil", 1.20, 2, 3, 0, 0, False)],
        "radiance": [("Sunlit Ward", 2.10, 1, 3, 0, 0, False)],
        "umbra":    [("Answer the Call", 2.30, 1, 3, 0, 0, False)],
    },
    "sekhmet": {
        "ember":    [("Eye of Ra (Def Break)", 4.80, 1, 3, 0.0, 0.0, False), ("Wrath of the Eye", 2.60, 1, 5, 0.0, 0.0, True)],
        "tide":     [("Red Nile Draught (Stun 70%) (Def Break 60%)", 4.00, 1, 3, 0, 0, False), ("Seven Thousand Jars", 2.40, 1, 5, 0, 0, True)],
        "gale":     [("Khamsin Claws (Def Break 35%)", 1.50, 3, 3, 0, 0, False), ("Roar of the Burning Wind", 2.30, 1, 5, 0, 0, True)],
        "radiance": [("Eye of the Disc (Crit) (Def Break 75%)", 3.60, 1, 3, 0, 0, False), ("Noon Without Shadow", 2.40, 1, 5, 0, 0, True)],
        "umbra":    [("Seven Arrows (Def Break 75%)", 4.00, 1, 3, 0, 0, False), ("Breath of Plague (Def Break 40%)", 2.30, 1, 5, 0, 0.50, True)],
    },
    "zeus": {
        "ember":    [("Thunderclap (Stun 55%)", 2.00, 1, 4, 0.0, 0.0, True), ("Keraunos", 5.00, 1, 5, 0.40, 0.0, False)],
        "tide":     [("Hail of Ombrios (Stun 70%)", 3.60, 1, 4, 0, 0, False), ("Deluge of Deucalion", 2.50, 1, 5, 0.30, 0, True)],
        "gale":     [("Ourios Gusts", 1.15, 4, 4, 0, 0, False), ("Crown of Storms", 2.40, 1, 5, 0, 0, True)],
        "radiance": [("Eye of Panoptes", 1.80, 1, 4, 0, 0, True), ("Aegis of Day (Crit)", 4.60, 1, 5, 0.40, 0, False)],
        "umbra":    [("Black Cloud (Stun 45%)", 1.90, 1, 4, 0, 0, True), ("Chthonic Bolt (Def Break 75%)", 4.60, 1, 5, 0.40, 0.50, False)],
    },
    "ares": {
        "ember":    [("War Frenzy", 0.0, 0, 3, 0.0, 0.0, False), ("Slaughter", 4.60, 1, 4, 0.0, 0.80, False)],
        "tide":     [("Bronze Tide (Stun 60%)", 3.40, 1, 3, 0, 0, False), ("Enyalios' Charge", 4.40, 1, 4, 0, 0.60, False)],
        "gale":     [("Screaming Charge", 1.35, 3, 3, 0, 0, False), ("Stormlance", 4.20, 1, 4, 0, 0.60, False)],
        "radiance": [("Aureate Strike (Crit)", 3.40, 1, 3, 0, 0, False), ("Spoils of War (Crit)", 4.40, 1, 4, 0, 0, False)],
        "umbra":    [("Black Standard (Def Break 60%)", 3.60, 1, 3, 0, 0, False), ("Brotoloigos", 4.00, 1, 4, 0, 1.00, False)],
    },
    "heracles": {
        "ember":    [("Nemean Roar", 1.60, 1, 4, 0.0, 0.0, True), ("Twelve Labours", ("hp", 0.30), 1, 4, 0.30, 0.0, False)],
        "tide":     [("Augean Flood", 1.50, 1, 4, 0, 0, True), ("Bull of Crete (Stun 70%)", ("hp", 0.26), 1, 4, 0, 0, False)],
        "gale":     [("Chase of the Hind", 2.60, 1, 4, 0, 0, False), ("Stymphalian Storm", ("hp", 0.24), 1, 5, 0, 0, True)],
        "radiance": [("Hold the Sky", 0.0, 0, 4, 0, 0, False), ("Golden Apples (Crit)", ("hp", 0.28), 1, 4, 0, 0, False)],
        "umbra":    [("Leash of Cerberus (Def Break 60%)", 2.80, 1, 4, 0, 0, False), ("Gate of Erebos", ("hp", 0.30), 1, 4, 0, 0, False)],
    },
    "perseus": {
        "ember":    [("Bronze Blade (Burn 50%)", 1.80, 2, 3, 0.25, 0.0, False), ("Gorgon's Blood (Burn 60%)", 2.20, 1, 5, 0.0, 0.0, True)],
        "tide":     [("Cetus Cut (Stun 65%)", 3.40, 1, 3, 0, 0, False), ("Stone Tide (Stun 40%)", 2.20, 1, 5, 0, 0, True)],
        "gale":     [("Winged Cuts", 1.00, 4, 3, 0, 0, False), ("Sky-Walker's Dive", 2.10, 1, 5, 0, 0, True)],
        "radiance": [("Mirror Shield", 0.0, 0, 4, 0, 0, False), ("Gorgon's Gaze", 2.20, 1, 5, 0, 0, True)],
        "umbra":    [("Unseen Cut (Def Break 50%)", 3.40, 1, 3, 0, 0, False), ("Eye of the Unseen (Stun 40%)", 2.10, 1, 5, 0, 0.50, True)],
    },
    "thoth": {
        "ember":    [("Words of Fire", 0.0, 0, 4, 0.0, 0.0, False), ("Decree of Djehuty", 0.0, 0, 5, 0.0, 0.0, False)],
        "tide":     [("Words of Healing", 0.0, 0, 4, 0, 0, False), ("Book of the Dead", 0.0, 0, 5, 0, 0, False)],
        "gale":     [("Reading of the Winds", 0.0, 0, 4, 0, 0, False), ("Measured Year", 0.0, 0, 5, 0, 0, False)],
        "radiance": [("Silver Disc", 0.0, 0, 4, 0, 0, False), ("Word of Khemenu", 0.0, 0, 5, 0, 0, False)],
        "umbra":    [("Sealed Curse (Def Break 60%)", 2.60, 1, 3, 0, 0, False), ("Book of Secrets", 0.0, 0, 5, 0, 0, False)],
    },
    "hoplite": {
        "ember":    [("Spartan Thrust (Burn 60%)", 2.40, 1, 3, 0.0, 0.0, False)],
        "tide":     [("Phalanx", 0.0, 0, 4, 0, 0, False)],
        "gale":     [("Marathon Pace", 0.0, 0, 4, 0, 0, False)],
        "radiance": [("Delphic Ward", 0.0, 0, 4, 0, 0, False)],
        "umbra":    [("Theban Spear (Def Break 50%)", 2.40, 1, 3, 0, 0, False)],
    },
    "satyr": {
        "ember":    [("Bonfire Reel", 0.0, 0, 4, 0.0, 0.0, False)],
        "tide":     [("River Lullaby", 0.0, 0, 4, 0, 0, False)],
        "gale":     [("Wild Piping", 0.0, 0, 4, 0, 0, False)],
        "radiance": [("Noon Song", 0.0, 0, 4, 0, 0, False)],
        "umbra":    [("Night Dirge (Def Break 50%)", 2.20, 1, 3, 0, 0, False)],
    },
    "harpy": {
        "ember":    [("Cinder Dive (Burn 60%)", 2.50, 1, 3, 0.0, 0.0, False)],
        "tide":     [("Screech Dive", 2.60, 1, 3, 0, 0, False)],
        "gale":     [("Talon Flurry", 0.95, 3, 3, 0, 0, False)],
        "radiance": [("Snatching Dive", 2.40, 1, 3, 0, 0, False)],
        "umbra":    [("Carrion Dive (Def Break 50%)", 2.50, 1, 3, 0, 0, False)],
    },
}
HANDWRITTEN = [  # key, the reference blueprint: its stats stand for all five forms (`form` adds the premium)
    ("anubis", ANUBIS), ("shabti", SHABTI3), ("sekhmet", SEKHMET), ("zeus", ZEUS), ("ares", ARES),
    ("heracles", HERACLES), ("perseus", PERSEUS), ("thoth", THOTH), ("hoplite", HOPLITE),
    ("satyr", SATYR), ("harpy", HARPY),
]

def handwritten_skills(key, element, bp):
    """A hand-written family's kit for one element: the reference blueprint's
    basic attack, then the element's own second and third, a max-health blow
    resolved against the family's numbers."""
    skills = [bp.skills[0]]
    for name, mult, hits, cd, defign, missbonus, aoe in HANDWRITTEN_VARIANTS[key][element]:
        if isinstance(mult, tuple):
            mult = mult[1] * bp.hp / bp.atk
        skills.append((name, mult, hits, cd, defign, missbonus, aoe))
    return skills

for _key, _bp in HANDWRITTEN:
    assert handwritten_skills(_key, _bp.element, _bp) == _bp.skills, (
        f"{_bp.id}: the reference blueprint and HANDWRITTEN_VARIANTS[{_key!r}][{_bp.element!r}] disagree; "
        "change a kit in both, and in the Swift")


# The third roster: Pantheon/Core/Data/UnitDatabase+Families.swift, one row per
# family and one of eight kit shapes, mirrored here row for row. The sim sees
# the fire variant (attack x1.05) and reads burn, stun and defence break off
# the skill names; heals, shields, provokes and strips show up only as the
# damage they do not do, so a healer's row is a floor, not a forecast.
# The second and third skills are the element's own (UnitDatabase+Families.swift,
# `elementalSkill`): eight kits by five elements, mirrored here pair for pair
# in the sim's own terms. A max-health blow is written ("hp", fraction) and
# resolved against the family's numbers; Freeze and Sleep are a stun to the
# sim, and Slow, Silence, Provoke, Brand, Glancing, shields, heals and strips
# show up only as the damage they do not do.
ELEMENT_SKILLS = {
    ("striker", "ember"):    [("Twin Blows (Burn 50%)", 2.10, 2, 3, 0, 0, False), ("Pyre Sweep (Burn 60%)", 2.60, 1, 5, 0, 0, True)],
    ("striker", "tide"):     [("Crushing Blow (Stun 70%)", 3.80, 1, 4, 0, 0, False), ("Undertow Sweep", 2.40, 1, 5, 0, 0, True)],
    ("striker", "gale"):     [("Three Cuts", 1.45, 3, 3, 0, 0, False), ("Storm Sweep", 2.30, 1, 5, 0, 0, True)],
    ("striker", "radiance"): [("Shining Blow", 3.60, 1, 3, 0, 0, False), ("Judgement Sweep (Crit)", 2.40, 1, 5, 0, 0, True)],
    ("striker", "umbra"):    [("Draining Blow (Def Break 60%)", 3.50, 1, 3, 0, 0, False), ("Black Sweep", 2.30, 1, 5, 0, 0.5, True)],
    ("duelist", "ember"):    [("Piercing Blow (Burn 60%)", 4.20, 1, 4, 0.30, 0, False), ("Sure Crit (Crit)", 5.20, 1, 5, 0, 0, False)],
    ("duelist", "tide"):     [("Two Cuts (Stun 40%)", 2.10, 2, 4, 0, 0, False), ("Half-Guard Blow", 4.80, 1, 5, 0.50, 0, False)],
    ("duelist", "gale"):     [("Four Cuts", 1.10, 4, 3, 0, 0, False), ("Sure Crit (Crit)", 4.40, 1, 5, 0, 0, False)],
    ("duelist", "radiance"): [("Focused Blow", 4.00, 1, 4, 0, 0, False), ("Judgement (Crit)", 5.40, 1, 5, 0.40, 0, False)],
    ("duelist", "umbra"):    [("Draining Blow", 4.20, 1, 4, 0, 0, False), ("Execution (Crit)", 4.60, 1, 5, 0, 1.0, False)],
    ("marksman", "ember"):   [("Two Shots (Burn 50%)", 2.20, 2, 3, 0, 0, False), ("Burning Volley (Burn 60%)", 2.30, 1, 5, 0, 0, True)],
    ("marksman", "tide"):    [("Spread", 1.60, 3, 3, 0, 0, False), ("Freezing Volley (Stun 45%)", 2.20, 1, 5, 0, 0, True)],
    ("marksman", "gale"):    [("Five Shots", 1.05, 5, 3, 0, 0, False), ("Carrying Volley", 2.00, 1, 5, 0, 0, True)],
    ("marksman", "radiance"): [("Stripping Shot", 4.00, 1, 3, 0, 0, False), ("Revealing Volley", 2.20, 1, 5, 0, 0, True)],
    ("marksman", "umbra"):   [("Draining Shot (Def Break 60%)", 3.60, 1, 3, 0, 0, False), ("Sleeping Volley (Stun 40%)", 2.10, 1, 5, 0, 0, True)],
    ("bruiser", "ember"):    [("Burning Slam (Burn 70%)", 2.40, 1, 4, 0, 0, False), ("Body Blow (Def Break 60%)", ("hp", 0.28), 1, 4, 0.30, 0, False)],
    ("bruiser", "tide"):     [("Roar", 1.50, 1, 4, 0, 0, True), ("Body Blow", ("hp", 0.28), 1, 4, 0.30, 0, False)],
    ("bruiser", "gale"):     [("Charge", 2.60, 1, 4, 0, 0, False), ("Line Body Blow", ("hp", 0.24), 1, 5, 0, 0, True)],
    ("bruiser", "radiance"): [("Shield Blow", 2.00, 1, 4, 0, 0, False), ("Body Blow", ("hp", 0.26), 1, 4, 0, 0, False)],
    ("bruiser", "umbra"):    [("Draining Blow (Def Break 60%)", 2.60, 1, 4, 0, 0, False), ("Body Blow", ("hp", 0.30), 1, 4, 0, 0, False)],
    ("warden", "ember"):     [("Burning Strike (Burn 70%)", 3.00, 1, 4, 0, 0, False), ("Team Attack Up", 0.0, 0, 5, 0, 0, False)],
    ("warden", "tide"):      [("Shield Wall", 0.0, 0, 4, 0, 0, False), ("Freezing Strike (Stun 70%)", 3.40, 1, 5, 0, 0, False)],
    ("warden", "gale"):      [("Team Haste", 0.0, 0, 4, 0, 0, False), ("Provoking Strike", 3.20, 1, 5, 0, 0, False)],
    ("warden", "radiance"):  [("Shield Cleanse", 0.0, 0, 4, 0, 0, False), ("Provoking Strike", 3.20, 1, 5, 0, 0, False)],
    ("warden", "umbra"):     [("Draining Strike (Def Break 60%)", 3.20, 1, 4, 0, 0, False), ("Branding Strike", 3.60, 1, 5, 0, 0, False)],
    ("healer", "ember"):     [("Warm Heal", 0.0, 0, 4, 0, 0, False), ("Phoenix Rite", 0.0, 0, 5, 0, 0, False)],
    ("healer", "tide"):      [("Team Heal", 0.0, 0, 4, 0, 0, False), ("Guarding Heal", 0.0, 0, 5, 0, 0, False)],
    ("healer", "gale"):      [("Quick Heal", 0.0, 0, 4, 0, 0, False), ("Team Haste", 0.0, 0, 5, 0, 0, False)],
    ("healer", "radiance"):  [("Shielding Heal", 0.0, 0, 4, 0, 0, False), ("Blessing", 0.0, 0, 5, 0, 0, False)],
    ("healer", "umbra"):     [("Draining Strike", 2.80, 1, 3, 0, 0, False), ("Focus Rite", 0.0, 0, 5, 0, 0, False)],
    ("oracle", "ember"):     [("Control (Stun 40%)", 1.60, 1, 4, 0, 0, True), ("Surge", 0.0, 0, 5, 0, 0, False)],
    ("oracle", "tide"):      [("Slowing Line", 1.50, 1, 4, 0, 0, True), ("Guard Rite", 0.0, 0, 5, 0, 0, False)],
    ("oracle", "gale"):      [("Silencing Line", 1.40, 1, 4, 0, 0, True), ("Team Haste", 0.0, 0, 5, 0, 0, False)],
    ("oracle", "radiance"):  [("Revealing Line", 1.50, 1, 4, 0, 0, True), ("Immunity Rite", 0.0, 0, 5, 0, 0, False)],
    ("oracle", "umbra"):     [("Sleeping Line (Stun 40%)", 1.60, 1, 4, 0, 0, True), ("Line Break (Def Break 60%)", 0.0, 0, 5, 0, 0, False)],
    ("trickster", "ember"):  [("Burning Strip (Burn 80%)", 3.20, 1, 3, 0, 0, False), ("Burning Line (Burn 60%)", 2.00, 1, 5, 0, 0, True)],
    ("trickster", "tide"):   [("Freezing Strike (Stun 70%)", 3.00, 1, 3, 0, 0, False), ("Slowing Line", 1.90, 1, 5, 0, 0, True)],
    ("trickster", "gale"):   [("Strip", 3.20, 1, 3, 0, 0, False), ("Silencing Line", 1.90, 1, 5, 0, 0, True)],
    ("trickster", "radiance"): [("Strip", 3.20, 1, 3, 0, 0, False), ("Revealing Line", 2.00, 1, 5, 0, 0, True)],
    ("trickster", "umbra"):  [("Strip", 3.40, 1, 3, 0, 0, False), ("Break (Def Break 60%)", 2.00, 1, 5, 0, 0, True)],
}
ELEMENTS = ["ember", "tide", "gale", "radiance", "umbra"]

def kit_skills(kit, stars, hp, atk, element="ember"):
    """A family's kit as the sim sees it: the kit's basic attack, then the
    element's second and third. The basic attack's burn stands for the
    element's signature; the sim has no slow, glance, attack-down or break
    to give the other four, so the fire variant reads a little strong."""
    basic = {"striker": ("Strike (Burn 30%)", 3.00), "duelist": ("Two Cuts (Burn 30%)", 1.50),
             "marksman": ("Shot (Burn 30%)", 2.90), "bruiser": ("Strike (Burn 30%)", 2.80),
             "warden": ("Strike (Burn 30%)", 2.70), "healer": ("Strike (Burn 30%)", 2.50),
             "oracle": ("Strike (Burn 30%)", 2.60), "trickster": ("Strike (Burn 40%)", 2.80)}[kit]
    hits = 2 if kit == "duelist" else 1
    s = [(basic[0], basic[1], hits, 0, 0, 0, False)]
    for name, mult, n, cd, defign, missbonus, aoe in ELEMENT_SKILLS[(kit, element)]:
        if isinstance(mult, tuple):
            mult = mult[1] * hp / atk
        s.append((name, mult, n, cd, defign, missbonus, aoe))
    return s[:2] if stars <= 3 else s

FAMILY_ROWS = [  # key, name, stars, kit, hp, atk, def, spd — the row in the Swift table
    ("horus", "Horus", 5, "duelist", 430, 39, 24, 108),
    ("isis", "Isis", 5, "healer", 540, 25, 31, 106),
    ("set", "Set", 4, "trickster", 470, 33, 23, 110),
    ("bastet", "Bastet", 4, "striker", 455, 34, 22, 114),
    ("sobek", "Sobek", 4, "bruiser", 600, 25, 31, 96),
    ("hathor", "Hathor", 4, "oracle", 510, 24, 29, 108),
    ("scarab_knight", "Scarab Knight", 3, "warden", 350, 21, 27, 95),
    ("mummy", "Mummy", 3, "trickster", 320, 23, 21, 92),
    ("jackal_warrior", "Jackal Warrior", 3, "striker", 300, 26, 19, 104),
    ("athena", "Athena", 5, "warden", 560, 30, 34, 104),
    ("poseidon", "Poseidon", 5, "bruiser", 580, 31, 30, 100),
    ("hades", "Hades", 5, "trickster", 500, 34, 28, 103),
    ("apollo", "Apollo", 4, "healer", 490, 28, 27, 110),
    ("artemis", "Artemis", 4, "marksman", 450, 33, 22, 115),
    ("hermes", "Hermes", 4, "oracle", 470, 29, 25, 122),
    ("minotaur", "Minotaur", 3, "bruiser", 380, 25, 24, 90),
    ("cyclops", "Cyclops", 3, "striker", 360, 28, 20, 88),
    ("amazon", "Amazon", 3, "duelist", 310, 26, 20, 106),
    ("medusa", "Medusa", 3, "oracle", 320, 24, 21, 100),
    ("odin", "Odin", 5, "oracle", 520, 33, 28, 108),
    ("thor", "Thor", 5, "striker", 470, 41, 26, 100),
    ("freya", "Freya", 5, "healer", 530, 27, 30, 107),
    ("loki", "Loki", 5, "trickster", 445, 37, 23, 112),
    ("tyr", "Tyr", 4, "bruiser", 570, 26, 32, 97),
    ("heimdall", "Heimdall", 4, "warden", 540, 27, 33, 102),
    ("hel", "Hel", 4, "trickster", 500, 31, 27, 101),
    ("skadi", "Skadi", 4, "marksman", 460, 32, 24, 112),
    ("valkyrie", "Valkyrie", 3, "duelist", 310, 26, 21, 108),
    ("draugr", "Draugr", 3, "warden", 360, 22, 26, 88),
    ("berserker", "Berserker", 3, "striker", 320, 28, 17, 103),
    ("frost_troll", "Frost Troll", 3, "bruiser", 400, 24, 25, 85),
    ("dwarf_smith", "Dwarf Smith", 3, "oracle", 330, 21, 24, 94),
    # batch 3 (UnitDatabase+Families.swift, the same order)
    ("ra", "Ra", 5, "marksman", 450, 38, 25, 104),
    ("osiris", "Osiris", 5, "healer", 560, 26, 32, 102),
    ("ptah", "Ptah", 4, "oracle", 500, 26, 30, 104),
    ("khnum", "Khnum", 4, "warden", 580, 25, 33, 96),
    ("nephthys", "Nephthys", 4, "trickster", 480, 32, 24, 110),
    ("maat", "Ma'at", 4, "healer", 520, 24, 30, 108),
    ("serqet", "Serqet", 4, "trickster", 460, 34, 23, 112),
    ("taweret", "Taweret", 4, "bruiser", 640, 24, 30, 92),
    ("anhur", "Anhur", 4, "duelist", 450, 36, 23, 110),
    ("bes", "Bes", 3, "oracle", 340, 22, 24, 100),
    ("medjay", "Medjay", 3, "marksman", 300, 26, 19, 106),
    ("cobra_priestess", "Cobra Priestess", 3, "healer", 330, 21, 23, 100),
    ("hera", "Hera", 5, "oracle", 530, 32, 29, 108),
    ("hephaestus", "Hephaestus", 4, "warden", 590, 28, 34, 94),
    ("demeter", "Demeter", 4, "healer", 540, 24, 30, 104),
    ("dionysus", "Dionysus", 4, "trickster", 470, 32, 24, 110),
    ("aphrodite", "Aphrodite", 4, "oracle", 500, 26, 27, 112),
    ("nike", "Nike", 4, "duelist", 440, 36, 22, 116),
    ("achilles", "Achilles", 4, "striker", 460, 36, 24, 108),
    ("atalanta", "Atalanta", 3, "marksman", 300, 26, 19, 110),
    ("siren", "Siren", 3, "oracle", 320, 24, 21, 104),
    ("nymph", "Nymph", 3, "healer", 330, 21, 23, 102),
    ("baldr", "Baldr", 5, "healer", 550, 27, 30, 106),
    ("frigg", "Frigg", 5, "oracle", 520, 31, 29, 110),
    ("surtr", "Surtr", 5, "striker", 500, 40, 26, 100),
    ("njord", "Njord", 4, "warden", 570, 27, 32, 100),
    ("idunn", "Idunn", 4, "healer", 510, 24, 29, 108),
    ("sif", "Sif", 4, "duelist", 450, 35, 24, 108),
    ("ullr", "Ullr", 4, "marksman", 440, 35, 23, 112),
    ("vidar", "Vidar", 4, "bruiser", 610, 26, 32, 94),
    ("fenrir", "Fenrir", 4, "striker", 480, 37, 23, 110),
    ("bragi", "Bragi", 4, "oracle", 490, 27, 26, 112),
    ("einherjar", "Einherjar", 3, "warden", 350, 22, 27, 96),
    ("shield_maiden", "Shield Maiden", 3, "duelist", 310, 26, 21, 108),
    ("light_elf", "Light Elf", 3, "healer", 320, 21, 22, 106),
    ("dark_elf", "Dark Elf", 3, "trickster", 310, 25, 20, 110),
    # batch 4: Rome, then the Jade Court (UnitDatabase+Families.swift,
    # `familyRowsRoman` and `familyRowsChinese`, the same order)
    ("mars", "Mars", 5, "striker", 480, 40, 27, 102),
    ("minerva", "Minerva", 5, "oracle", 525, 32, 30, 106),
    ("neptune", "Neptune", 4, "warden", 575, 27, 33, 98),
    ("pluto", "Pluto", 4, "trickster", 495, 32, 26, 104),
    ("diana", "Diana", 4, "marksman", 445, 34, 22, 116),
    ("mercury", "Mercury", 4, "duelist", 435, 35, 22, 120),
    ("bellona", "Bellona", 4, "bruiser", 590, 28, 30, 98),
    ("centurion", "Centurion", 3, "warden", 355, 22, 27, 94),
    ("gladiator", "Gladiator", 3, "striker", 315, 27, 19, 102),
    ("vestal", "Vestal", 3, "healer", 330, 21, 23, 101),
    ("sun_wukong", "Sun Wukong", 5, "trickster", 450, 37, 24, 113),
    ("azure_dragon", "Azure Dragon", 5, "marksman", 460, 38, 26, 104),
    ("nezha", "Nezha", 4, "striker", 450, 36, 23, 116),
    ("guan_yu", "Guan Yu", 4, "warden", 560, 29, 32, 100),
    ("chang_e", "Chang'e", 4, "healer", 515, 24, 29, 110),
    ("nuwa", "Nuwa", 4, "oracle", 510, 26, 30, 106),
    ("dragon_king", "Dragon King", 4, "bruiser", 620, 25, 31, 94),
    ("fox_spirit", "Fox Spirit", 3, "trickster", 315, 24, 21, 108),
    ("jiangshi", "Jiangshi", 3, "duelist", 320, 26, 21, 100),
    ("terracotta_soldier", "Terracotta Soldier", 3, "warden", 365, 21, 28, 90),
]
FAMILIES = {
    key: Blueprint(f"{key}_ember", f"{name} (Fire)", "ember", stars, hp=hp, atk=atk * 1.05, dfn=dfn, spd=spd,
                   skills=kit_skills(kit, stars, hp, atk * 1.05))
    for key, name, stars, kit, hp, atk, dfn, spd in FAMILY_ROWS
}

# The Greek and Norse campaign enemies and bosses (UnitDatabase.swift, the
# "Greek and Norse campaigns" block). Freeze is a stun to the sim.
E_MINOTAUR  = Blueprint("enemy_minotaur",  "Minotaur",   "umbra",    3,  390, 27, 25,  92,
    skills=[("Horn Toss", 1.60, 1, 0, 0, 0, False), ("Bull Rush", 3.00, 1, 3, 0, 0, False)])
E_CYCLOPS   = Blueprint("enemy_cyclops",   "Cyclops",    "ember",    3,  370, 30, 20,  88,
    skills=[("Club Smash", 1.70, 1, 0, 0, 0, False), ("Boulder Heave (Def Break 35%)", 2.40, 1, 3, 0, 0, True)])
E_AMAZON    = Blueprint("enemy_amazon",    "Amazon",     "gale",     3,  310, 28, 20, 108,
    skills=[("Labrys Cut", 1.70, 1, 0, 0, 0, False), ("Crescent Sweep (Def Break 40%)", 2.80, 1, 3, 0, 0, False)])
E_MEDUSA    = Blueprint("enemy_medusa",    "Medusa",     "radiance", 3,  330, 26, 21, 100,
    skills=[("Serpent Lash", 0.90, 2, 0, 0, 0, False), ("Petrifying Gaze (Stun 35%)", 2.00, 1, 4, 0, 0, False)])
HYDRA       = Blueprint("boss_hydra",      "Hydra",      "tide",     5, 1050, 40, 30,  92,
    skills=[("Three Bites", 0.80, 3, 0, 0, 0, False), ("Venom Breath (Def Break 50%)", 2.40, 1, 4, 0, 0, True)])
E_DRAUGR    = Blueprint("enemy_draugr",    "Draugr",     "umbra",    3,  370, 23, 27,  88,
    skills=[("Grave Axe", 1.60, 1, 0, 0, 0, False), ("Barrow Grip", 2.60, 1, 3, 0, 0, False)])
E_BERSERKER = Blueprint("enemy_berserker", "Berserker",  "ember",    3,  330, 30, 17, 103,
    skills=[("Twin Axes", 0.95, 2, 0, 0, 0, False), ("Bear Rage (Def Break 45%)", 3.20, 1, 3, 0, 0, False)])
E_VALKYRIE  = Blueprint("enemy_valkyrie",  "Valkyrie",   "radiance", 3,  315, 27, 21, 108,
    skills=[("Spear Thrust", 1.70, 1, 0, 0, 0, False), ("Chooser's Cut", 3.00, 1, 3, 0, 0, False)])
E_TROLL     = Blueprint("enemy_frost_troll", "Frost Troll", "tide",  3,  430, 25, 26,  84,
    skills=[("Ice Club", 1.60, 1, 0, 0, 0, False), ("Glacier Roar (Stun 30%)", 2.40, 1, 4, 0, 0, True)])
JOTUNN      = Blueprint("boss_jotunn",     "Jotunn",     "gale",     5, 1150, 37, 34,  88,
    skills=[("Ice Axe", 1.90, 1, 0, 0, 0, False), ("Avalanche (Stun 35%)", 2.60, 1, 4, 0, 0, True)])
# The Roman and Chinese campaign enemies and bosses (UnitDatabase.swift, the
# "Roman and Chinese campaigns" block).
E_CENTURION = Blueprint("enemy_centurion", "Centurion", "umbra", 3, 380, 24, 27, 92,
    skills=[("Gladius Thrust", 1.60, 1, 0, 0, 0, False), ("Pilum Cast (Def Break 40%)", 2.80, 1, 3, 0, 0, False)])
E_GLADIATOR = Blueprint("enemy_gladiator", "Gladiator", "ember", 3, 330, 30, 18, 104,
    skills=[("Arena Cut", 1.70, 1, 0, 0, 0, False), ("Crowd's Roar (Def Break 40%)", 3.10, 1, 3, 0, 0, False)])
E_VESTAL    = Blueprint("enemy_vestal", "Vestal", "radiance", 3, 340, 25, 22, 102,
    skills=[("Ember Cast", 0.90, 2, 0, 0, 0, False), ("Sacred Fire (Burn 40%)", 2.00, 1, 4, 0, 0, True)])
E_PRAETORIAN = Blueprint("enemy_praetorian", "Praetorian", "tide", 3, 400, 25, 26, 90,
    skills=[("Pilum Thrust", 1.60, 1, 0, 0, 0, False), ("Shield Bash (Stun 35%)", 2.60, 1, 4, 0, 0, False)])
BRONZE      = Blueprint("boss_bronze_colossus", "Colossus of the Sun", "ember", 5, 1200, 38, 36, 84,
    skills=[("Bronze Fist", 1.90, 1, 0, 0, 0, False), ("Sun-Crown Blaze (Burn 45%)", 2.70, 1, 4, 0, 0, True)])
E_JIANGSHI  = Blueprint("enemy_jiangshi", "Jiangshi", "umbra", 3, 335, 28, 21, 96,
    skills=[("Stiff Claws", 0.90, 2, 0, 0, 0, False), ("Hopping Lunge (Def Break 40%)", 3.00, 1, 3, 0, 0, False)])
E_TERRACOTTA = Blueprint("enemy_terracotta_soldier", "Terracotta Soldier", "radiance", 3, 420, 24, 28, 86,
    skills=[("Bronze Halberd", 1.60, 1, 0, 0, 0, False), ("Ranks of Clay (Def Break 35%)", 2.40, 1, 4, 0, 0, True)])
E_FOX       = Blueprint("enemy_fox_spirit", "Fox Spirit", "gale", 3, 320, 27, 21, 110,
    skills=[("Fox-Fire", 1.70, 1, 0, 0, 0, False), ("Beguiling Glance (Stun 35%)", 2.00, 1, 4, 0, 0, False)])
E_GENERAL   = Blueprint("enemy_terracotta_general", "Terracotta General", "ember", 3, 440, 27, 27, 88,
    skills=[("Halberd Sweep", 1.60, 1, 0, 0, 0, False), ("Kiln-Fired Charge (Def Break 45%)", 2.80, 1, 3, 0, 0, False)])
LONGMEN     = Blueprint("boss_longmen_dragon", "Dragon of Longmen", "tide", 5, 1100, 41, 31, 90,
    skills=[("Fang and Coil", 0.85, 3, 0, 0, 0, False), ("Flood of the Falls (Stun 35%)", 2.50, 1, 4, 0, 0, True)])
# The Labyrinth's own bosses (UnitDatabase.swift, "The Labyrinth's bosses").
COLOSSUS    = Blueprint("boss_colossus",   "Colossus",   "radiance", 5, 1250, 36, 40,  80,
    skills=[("Stone Fist", 1.90, 1, 0, 0, 0, False), ("Fall of the Colossus (Stun 30%)", 2.80, 1, 4, 0, 0, True)])
UNWRAPPED   = Blueprint("boss_unwrapped_king", "Unwrapped King", "umbra", 5, 1000, 42, 30, 96,
    skills=[("Crook and Flail", 0.95, 2, 0, 0, 0, False), ("Weight of the Ledger", 2.60, 1, 4, 0, 0, True)])

def mk(bp, level, stars, relic=1.0, boss=1.0):
    f = Fighter(bp, level, stars, relic)
    if boss != 1.0:
        f.maxhp *= boss; f.hp = f.maxhp; f.atk *= boss; f.dfn *= boss
    f.is_boss = bp.id in BOSS_IDS
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
    # THREE WAVES a stage since 2026-09-15 (the owner: "most bosses and
    # levels are 3 waves, 1 being a boss"), mirroring StageDatabase's Duat 1:
    # two weaker waves (x0.75, x0.85), then the wave with the leader or the
    # boss. A stage's spec is a list of waves; the team carries its wounds.
    ("1-1 The First Gate",    400, [[(SHABTI,4,2,0.75),(SHABTI,4,2,0.75)],
                                    [(SHABTI,5,2,0.85),(SHABTI,5,2,0.85)],
                                    [(SHABTI,5,2),(SHABTI,6,3,1.2)]]),
    ("1-2 Reed Fields",       800, [[(SHABTI,7,2,0.75),(SHABTI,7,2,0.75)],
                                    [(SHABTI,8,2,0.85),(SERPOPARD,8,3,0.85)],
                                    [(SHABTI,8,2),(SERPOPARD,9,3,1.25)]]),
    ("1-3 Scarab Court",     1800, [[(SHABTI,13,2,0.75),(SERPOPARD,13,3,0.75)],
                                    [(SERPOPARD,14,3,0.85),(SHABTI,14,2,0.85)],
                                    [(SERPOPARD,14,3),(SCARAB,15,4,1.25),(SHABTI,14,2)]]),
    ("1-4 Hall of Sentinels",3600, [[(SERPOPARD,19,3,0.75),(SCARAB,19,3,0.75),(SHABTI,19,2,0.75)],
                                    [(SENTINEL,20,3,0.85),(SERPOPARD,20,3,0.85),(SCARAB,20,3,0.85)],
                                    [(SENTINEL,20,3),(AMMIT,21,4,1.3),(SERPOPARD,20,3)]]),
    ("1-5 Coils of Apep",    7000, [[(SERPOPARD,25,3,0.75),(SCARAB,25,3,0.75),(SHABTI,25,2,0.75)],
                                    [(SENTINEL,26,3,0.85),(SERPOPARD,26,3,0.85),(AMMIT,26,4,0.85)],
                                    [(SENTINEL,26,3),(APEP,28,5,1.42),(AMMIT,26,4)]]),
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
    for bp, ladder in ((ANUBIS, [(4,1),(4,45),(5,1),(5,55),(6,1),(6,65)]),
                       (SEKHMET, [(5,1),(5,55),(6,1),(6,65)]),
                       (ZEUS, [(5,1),(5,55),(6,1),(6,65)])):
        print(f"\n{bp.name.upper()} STAT CURVE")
        print(f"{'grade/level':>14}{'HP':>9}{'ATK':>7}{'DEF':>7}{'SPD':>6}{'power':>9}")
        for stars, lvl in ladder:
            f = mk(bp, lvl, stars)
            print(f"{f'{stars}* lv{lvl}':>14}{f.maxhp:>9.0f}{f.atk:>7.0f}{f.dfn:>7.0f}{f.spd:>6.0f}{f.power():>9}")
        g = mk(bp, 55, 6, 1.60)
        print(f"{'6* lv55 geared':>14}{g.maxhp:>9.0f}{g.atk:>7.0f}{g.dfn:>7.0f}{g.spd:>6.0f}{g.power():>9}")

def report_duel(trials=300):
    """One on one at equal grade and level. The attacker should beat the support
    a majority of the time but not all of it, or the support kit is pointless;
    the controller should sit between them, and beat the attacker only when the
    stun lands often enough to matter."""
    print("\nDUEL — 1v1, same grade and level, %d seeded fights" % trials)
    for a, b in ((SEKHMET, ANUBIS), (ZEUS, ANUBIS), (ZEUS, SEKHMET), (ANUBIS, SHABTI3),
                 (ARES, SEKHMET), (ARES, ZEUS), (HERACLES, ANUBIS), (PERSEUS, ANUBIS),
                 (THOTH, ANUBIS), (HOPLITE, SHABTI3), (HARPY, SHABTI3), (SATYR, SHABTI3)):
        an, bn = a.name.split()[0], b.name.split()[0]
        for stars, lvl in [(5, 1), (5, 30), (6, 55)]:
            wins = sum(1 for s in range(trials)
                       if simulate([mk(a, lvl, stars)], [mk(b, lvl, stars)], seed=s)[0] == "a")
            print(f"  {stars}* lv{lvl:<3}  {an} vs {bn:<8} {an} wins {wins / trials * 100:3.0f}%")

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
    # A summoned Sekhmet beside three Anubis: what one real damage dealer does
    # to a support-only team's curve.
    ("3x A lv35 + Sekhmet",[(ANUBIS, 35, 4, 1.15)] * 3 + [(SEKHMET, 35, 5, 1.15)]),
    # And a summoned Zeus instead: what one stun on the enemy line does.
    ("3x A lv35 + Zeus",   [(ANUBIS, 35, 4, 1.15)] * 3 + [(ZEUS, 35, 5, 1.15)]),
]

# The generated chapters, mirroring StageDatabase.generatedChapter: level =
# start + (i-1)*step, count = 4 on the boss stage else min(4, 2 + i/3), the
# roster rotated by stage, the boss in the last slot at x1.4, power =
# 2500 * scale * 1.18^(i-1).
# Every mob fights at the chapter's grade (`stars`, None = its own) times a
# chapter-wide `difficulty`; the boss keeps its own grade when higher and
# stands at x1.4 on top. Levels stay in the range the player's own units use.
CHAPTERS = [  # name, start level, step, stages, power scale, roster, boss, stars, difficulty
    ("Duat 2 Gates of the West",      30, 3, 10,  1.0, [SHABTI, SERPOPARD, SCARAB, SENTINEL, AMMIT], AMMIT, None, 1.0),
    ("Olympus 1 Gate of Olympus",     30, 2, 10,  2.2, [E_AMAZON, E_CYCLOPS, E_MINOTAUR, E_MEDUSA], E_CYCLOPS, 4, 1.0),
    ("Olympus 2 Aegean Cliffs",       34, 2, 10,  3.2, [E_MEDUSA, E_AMAZON, E_MINOTAUR, E_CYCLOPS], E_MEDUSA, 4, 1.25),
    ("Olympus 3 Marsh of Lerna",      38, 2, 10,  4.4, [E_MINOTAUR, E_MEDUSA, E_CYCLOPS, E_AMAZON], HYDRA, 4, 1.5),
    ("Yggdrasil 1 Midgard Fjord",     40, 2, 10,  6.0, [E_DRAUGR, E_BERSERKER, E_VALKYRIE, E_TROLL], E_BERSERKER, 5, 1.2),
    ("Yggdrasil 2 Roots of the Tree", 44, 2, 10,  8.0, [E_VALKYRIE, E_TROLL, E_DRAUGR, E_BERSERKER], E_TROLL, 5, 1.45),
    ("Yggdrasil 3 Hall of Jotunheim", 48, 2, 10, 10.5, [E_TROLL, E_DRAUGR, E_BERSERKER, E_VALKYRIE], JOTUNN, 5, 1.7),
    # Rome and the Jade Court carry the curve past Jotunheim: the Norse grade
    # at a higher level, then the roster a grade up (a 6* is x1.35 on every
    # stat, so the difficulty dial drops when the grade rises), a level a
    # stage so the top of the map is 68. Measured 2026-09-11 at 100 trials:
    # the maxed 6* team takes Rome 1's boss at 96t and Rome 2's at 130t, the
    # gods both in the sixties; Jade 1's boss is 96% for the 6*s at 139t and
    # 63t for the gods; Jade 2's dragon is out of the 6*s' reach (31% at
    # the cap) and 94t for the gods, which is the end of the map.
    ("Rome 1 Forum at Midnight",       50, 1, 10, 13.5, [E_CENTURION, E_GLADIATOR, E_VESTAL, E_PRAETORIAN], E_CENTURION, 5, 2.5),
    ("Rome 2 Sand of the Colosseum",   53, 1, 10, 17.0, [E_GLADIATOR, E_PRAETORIAN, E_CENTURION, E_VESTAL], BRONZE, 6, 1.45),
    ("Jade 1 Peach Garden",            56, 1, 10, 21.0, [E_JIANGSHI, E_TERRACOTTA, E_FOX, E_GENERAL], E_FOX, 6, 2.1),
    ("Jade 2 Dragon King's Gate",      59, 1, 10, 26.0, [E_GENERAL, E_FOX, E_JIANGSHI, E_TERRACOTTA], LONGMEN, 6, 1.45),
]

def generated_waves(chapter, index):
    """The three waves of a generated stage, mirroring generatedChapter:
    min(3, 2 + i//4) mobs at x0.75, the same count at x0.85 (the roster
    rotated two on), then two adds at x1.0 with the chapter's boss at x1.4
    on the last stage or a leader of the roster a grade up, a step higher
    in level and x1.3 on every other."""
    _, start, step, stages, scale, roster, boss, stars, difficulty = chapter
    is_boss = index == stages
    level = start + (index - 1) * step
    def mob(slot, wave, mult):
        bp = roster[(index + slot + wave * 2) % len(roster)]
        return (bp, level, stars or bp.stars, difficulty * mult)
    mobs = min(3, 2 + index // 4)
    first = [mob(slot, 0, 0.75) for slot in range(mobs)]
    second = [mob(slot, 1, 0.85) for slot in range(mobs)]
    last = [mob(slot, 2, 1.0) for slot in range(2)]
    if is_boss:
        last.append((boss, level, max(stars or boss.stars, boss.stars), difficulty * 1.4))
    else:
        leader = roster[index % len(roster)]
        last.append((leader, min(60, level + step), min(6, (stars or leader.stars) + 1), difficulty * 1.3))
    return [first, second, last], int(2500 * scale * 1.18 ** (index - 1))

def generated_stage(chapter, index):
    """The last wave alone, for the probes that want one fight."""
    waves, power = generated_waves(chapter, index)
    return waves[-1], power

CHAPTER_LADDERS = [
    ("4x 4* lv35",          [(ANUBIS, 35, 4, 1.15)] * 4),
    ("4x 5* lv40 +relics",  [(ANUBIS, 40, 5, 1.25)] * 4),
    ("4x 6* lv55 max",      [(ANUBIS, 55, 6, 1.60)] * 4),
    ("gods 6* lv60 max",    [(THOR := FAMILIES["thor"], 60, 6, 1.60), (SEKHMET, 60, 6, 1.60),
                             (FAMILIES["athena"], 60, 6, 1.60), (FAMILIES["isis"], 60, 6, 1.60)]),
]

def report_chapters(trials=100):
    print("\nCHAPTERS — generated stages 1, 5 and the boss, win rate over %d seeded battles" % trials)
    print("target: each chapter opens where one ladder step clears it and closes where the next is needed\n")
    print(f"{'stage':>36}{'lvl':>5}{'rec.pwr':>9}  " + "".join(f"{n:>22}" for n, _ in CHAPTER_LADDERS))
    for ch in CHAPTERS:
        for index in (1, 5, ch[3]):
            waves, power = generated_waves(ch, index)
            label = ch[0] + (" BOSS" if index == ch[3] else f" -{index}")
            row = f"{label:>36}{waves[0][0][1]:>5}{power:>9}  "
            for _, team in CHAPTER_LADDERS:
                wr, med = winrate_waves(team, waves, trials=trials)
                row += f"{wr*100:>16.0f}% {med:>3.0f}t"
            print(row)

# The campaign's tiers, mirroring CampaignDifficulty in StageDatabase.swift:
# grade +1 / +2 (capped at 6), level x1.15 / x1.25 (capped at 60), stats
# x1.2 / x1.5 on top of whatever the spawn already carried (a boss keeps its
# x1.4). Measured 2026-09-10: Hard's bosses fall to the third ladder step
# (Olympus 3 at 97% in 138 turns) and Hell's to the fourth (Yggdrasil 3 at
# 98% in 126 turns); at x1.3 / x1.7 Hell stalled even the gods at the cap.
DIFFICULTIES = [  # name, grade bonus, level scale, stat scale
    ("Normal", 0, 1.00, 1.0),
    ("Hard",   1, 1.15, 1.2),
    ("Hell",   2, 1.25, 1.5),
]

def tiered(spec, tier):
    _, bonus, lvl_scale, stat_scale = tier
    out = []
    for e in spec:
        bp, level, grade = e[0], e[1], e[2]
        mult = e[3] if len(e) > 3 else 1.0
        out.append((bp, min(60, round(level * lvl_scale)), min(6, grade + bonus), mult * stat_scale))
    return out

def report_tiers(trials=100):
    print("\nTIERS — boss stages at Normal, Hard and Hell, win rate over %d seeded battles" % trials)
    print("target: Hard clears at the third ladder step, Hell at the fourth, and Normal is untouched\n")
    print(f"{'stage':>36}{'tier':>7}  " + "".join(f"{n:>22}" for n, _ in CHAPTER_LADDERS))
    probes = [("Duat 1 Coils of Apep BOSS", STAGES[-1][2])]
    for ch in (CHAPTERS[0], CHAPTERS[3], CHAPTERS[6]):
        waves, _ = generated_waves(ch, ch[3])
        probes.append((ch[0] + " BOSS", waves))
    for name, waves in probes:
        for tier in DIFFICULTIES:
            row = f"{name:>36}{tier[0]:>7}  "
            for _, team in CHAPTER_LADDERS:
                wr, med = winrate_waves(team, [tiered(w, tier) for w in waves], trials=trials)
                row += f"{wr*100:>16.0f}% {med:>3.0f}t"
            print(row)

def report_variants(trials=120):
    """The five elemental forms of one family per kit against the Anubis
    benchmark, then the five forms of every hand-written family. What it
    measures: whether the elemental second and third skills keep a family's
    five forms within a band of each other, so no element is the one to
    summon. The sim cannot see slows, shields, heals, strips or the bar, so a
    healer's or a warden's spread is a floor; and the benchmark is dark, so a
    light form fights it at the wheel's mutual advantage and a dark one at
    neutral, which the light column carries."""
    print("\nELEMENTAL VARIANTS — one family per kit, win rate vs. Anubis (Lv.30 5*, relics 1.25), 1v1")
    firsts = {}
    for key, name, stars, kit, hp, atk, dfn, spd in FAMILY_ROWS:
        if kit not in firsts and stars >= 4:
            firsts[kit] = (key, name, stars, hp, atk, dfn, spd)
    print(f"  {'family':<14}{'kit':>10}" + "".join(f"{e[:4]:>8}" for e in ELEMENTS) + f"{'spread':>9}")
    for kit, (key, name, stars, hp, atk, dfn, spd) in firsts.items():
        rates = []
        for element in ELEMENTS:
            bp = premium(Blueprint(f"{key}_{element}", name, element, stars, hp=hp, atk=atk, dfn=dfn, spd=spd,
                                   skills=kit_skills(kit, stars, hp, atk, element)))
            rates.append(winrate_bp(bp, ANUBIS, trials))
        print(f"  {name:<14}{kit:>10}" + "".join(f"{r*100:>7.0f}%" for r in rates) + f"{(max(rates)-min(rates))*100:>8.0f}%")

    # A 3* family is measured against the dark Shabti, the 3* benchmark the
    # duel report uses, because a 3* never beats a 4* on the same grade and
    # level and a row of zeros measures nothing.
    print("\n  the hand-written families, five forms each on the family's own numbers (HANDWRITTEN_VARIANTS);")
    print("  a 4*+ family vs. Anubis, a 3* family vs. the dark Shabti; the light and dark columns carry the premium")
    print(f"  {'family':<14}{'grade':>10}" + "".join(f"{e[:4]:>8}" for e in ELEMENTS) + f"{'spread':>9}")
    for key, bp in HANDWRITTEN:
        foe = ANUBIS if bp.stars >= 4 else SHABTI3
        rates = []
        for element in ELEMENTS:
            shape = form(bp, element, id=f"{key}_{element}", skills=handwritten_skills(key, element, bp))
            rates.append(winrate_bp(shape, foe, trials))
        name = bp.name.split(" (")[0]
        print(f"  {name:<14}{bp.stars:>9}*" + "".join(f"{r*100:>7.0f}%" for r in rates) + f"{(max(rates)-min(rates))*100:>8.0f}%")

    report_premium(trials)

def premium_measure(bp, trials):
    """One form against the benchmark, seeded: mean damage dealt per action it
    takes, its win rate, and — against a wall it cannot beat (the benchmark at
    6* Lv.60 with relics 1.6) — the damage it absorbs before it falls, which
    is its survival with the skills held still."""
    dealt, actions, wins = 0.0, 0.0, 0
    for t in range(trials):
        st = {}
        result, _ = simulate([mk(bp, 30, 5, 1.25)], [mk(ANUBIS, 30, 5, 1.25)], seed=t, stats=st)
        dealt += st.get("dealt", {}).get("a", 0.0)
        actions += st.get("turns", {}).get("a", 0.0)
        wins += result == "a"
    absorbed = 0.0
    wall_trials = max(20, trials // 3)
    for t in range(wall_trials):
        st = {}
        simulate([mk(bp, 30, 5, 1.25)], [mk(ANUBIS, 60, 6, 1.60)], seed=1000 + t, stats=st)
        absorbed += st.get("taken", {}).get("a", 0.0)
    # Damage per action is the attack's own lift through the defence formula,
    # diluted by the rites and heals in the mix; damage per FIGHT is what the
    # premium buys on the field, the longer life included.
    return dealt / max(1.0, actions), dealt / trials, wins / trials, absorbed / wall_trials

def report_premium(trials=120):
    """What the Light and Dark premium buys, with the skills held still: the
    same Radiance or Umbra form with and without x1.08 on attack, health and
    defence (LIGHT_DARK_PREMIUM), on one family per kit and the hand-written
    4*+ families. Offence is damage per action against the benchmark;
    survival is damage absorbed before falling to a wall; and the win rate
    against the form's own fire, water and wind siblings says whether the
    premium form is the one to have. The band the owner asked for is a clear
    lead that is not a second grade: 6-20% on the isolated lifts."""
    print(f"\n  THE LIGHT AND DARK PREMIUM (UnitDatabase.lightDarkPremium x{LIGHT_DARK_PREMIUM:.2f} on attack, health, defence)")
    print("  the same form with and without it, skills held still, 1v1 at 5* Lv.30 +relics: damage per action and per fight")
    print("  vs. Anubis, damage absorbed before falling to a 6* Lv.60 wall, win rate vs. Anubis, and mean win rate vs. its own")
    print("  three fire, water and wind siblings")
    print(f"  {'form':<22}{'dmg/action':>11}{'dmg/fight':>10}{'absorbed':>10}{'vs Anubis':>16}{'vs siblings':>16}")
    samples = []
    seen = set()
    for key, name, stars, kit, hp, atk, dfn, spd in FAMILY_ROWS:
        if kit not in seen and stars >= 4:
            seen.add(kit)
            def table_form(element, key=key, name=name, stars=stars, kit=kit, hp=hp, atk=atk, dfn=dfn, spd=spd):
                return Blueprint(f"{key}_{element}", name, element, stars, hp=hp, atk=atk, dfn=dfn, spd=spd,
                                 skills=kit_skills(kit, stars, hp, atk, element))
            samples.append((name, table_form))
    for key, bp in HANDWRITTEN:
        if bp.stars >= 4:
            def hand_form(element, key=key, bp=bp):
                return replace(bp, id=f"{key}_{element}", element=element, skills=handwritten_skills(key, element, bp))
            samples.append((bp.name.split(" (")[0], hand_form))
    action_lifts, fight_lifts, survival_lifts, sibling_plain, sibling_lifted = [], [], [], [], []
    anubis_plain, anubis_lifted = [], []
    sibling_trials = max(20, trials // 2)
    for name, build in samples:
        for element in LIGHT_DARK:
            plain = build(element)
            lifted = premium(plain)
            assert lifted.hp > plain.hp, "a light or dark form must carry the premium"
            pa, pf, pw, ps = premium_measure(plain, trials)
            la, lf, lw, ls = premium_measure(lifted, trials)
            siblings = [build(e) for e in ("ember", "tide", "gale")]
            sp = statistics.mean(winrate_bp(plain, s, sibling_trials) for s in siblings)
            sl = statistics.mean(winrate_bp(lifted, s, sibling_trials) for s in siblings)
            action_lifts.append(la / pa if pa else 1.0)
            fight_lifts.append(lf / pf if pf else 1.0)
            survival_lifts.append(ls / ps if ps else 1.0)
            sibling_plain.append(sp); sibling_lifted.append(sl)
            anubis_plain.append(pw); anubis_lifted.append(lw)
            print(f"  {name + ' (' + element[:4] + ')':<22}{(la / pa - 1) * 100 if pa else 0:>+10.1f}%"
                  f"{(lf / pf - 1) * 100 if pf else 0:>+9.1f}%"
                  f"{(ls / ps - 1) * 100 if ps else 0:>+9.1f}%"
                  f"{pw * 100:>8.0f}% -> {lw * 100:>3.0f}%{sp * 100:>8.0f}% -> {sl * 100:>3.0f}%")
    per_action = statistics.mean(action_lifts)
    per_fight = statistics.mean(fight_lifts)
    survival = statistics.mean(survival_lifts)
    print(f"\n  mean lift: damage per action x{per_action:.3f}, damage per fight x{per_fight:.3f}, damage absorbed x{survival:.3f};")
    print(f"  win rate vs. own siblings {statistics.mean(sibling_plain) * 100:.0f}% -> {statistics.mean(sibling_lifted) * 100:.0f}%, "
          f"vs. Anubis {statistics.mean(anubis_plain) * 100:.0f}% -> {statistics.mean(anubis_lifted) * 100:.0f}%")
    band = (1.06, 1.20)
    assert band[0] <= per_fight <= band[1], f"the premium's damage-per-fight lift is {per_fight:.3f}: outside 6-20%, change LIGHT_DARK_PREMIUM and lightDarkPremium together"
    assert band[0] <= survival <= band[1], f"the premium's survival lift is {survival:.3f}: outside 6-20%, change LIGHT_DARK_PREMIUM and lightDarkPremium together"
    assert statistics.mean(sibling_lifted) > statistics.mean(sibling_plain) + 0.05, "the premium form should be the one to have"
    assert statistics.mean(sibling_lifted) < 0.85, "a premium form that beats its siblings almost always is a grade, not a premium"
    print("  -> a clear lead over the family's other forms and nothing like a grade (a 5* over a 4* is x1.3 on every stat)  -> correct")

def winrate_bp(bp, foe, trials):
    wins = 0
    for t in range(trials):
        a = [mk(bp, 30, 5, 1.25)]
        b = [mk(foe, 30, 5, 1.25)]
        result, _ = simulate(a, b, seed=t)
        wins += result == "a"
    return wins / trials

def report_families(trials=120):
    """Every family of the third roster, fire variant, 5* lv30 with relics, one
    on one against Anubis (a support) and Sekhmet (an attacker) at the same
    grade and level. Attackers should beat Anubis and split with Sekhmet;
    tanks and healers lose to Sekhmet slowly; nothing wins everything."""
    print("\nFAMILIES — 1v1 at 5* lv30 +relics, %d seeded fights each" % trials)
    print(f"  {'family':<16}{'*':>2}{'kit':>11}{'power':>8}{'vs Anubis':>11}{'vs Sekhmet':>12}")
    for key, name, stars, kit, *_ in FAMILY_ROWS:
        bp = FAMILIES[key]
        wa = sum(1 for s in range(trials) if simulate([mk(bp, 30, 5, 1.25)], [mk(ANUBIS, 30, 5, 1.25)], seed=s)[0] == "a") / trials
        ws = sum(1 for s in range(trials) if simulate([mk(bp, 30, 5, 1.25)], [mk(SEKHMET, 30, 5, 1.25)], seed=s)[0] == "a") / trials
        print(f"  {name:<16}{stars:>2}{kit:>11}{mk(bp, 30, 5, 1.25).power():>8,}{wa*100:>10.0f}%{ws*100:>11.0f}%")

# The Halls of Essence, mirroring DungeonDatabase.hall: five floors, three
# mobs of the element's roster at the floor's grade plus the boss at x1.4,
# level 20 + 8f, grade min(6, 3 + f), difficulty 0.75 + 0.10f.
HALLS = [  # name, roster, boss
    ("Hall of Embers",   [E_CYCLOPS, E_BERSERKER, SENTINEL], APEP),
    ("Hall of Tides",    [E_TROLL, E_TROLL, E_AMAZON], HYDRA),
    ("Hall of Gales",    [SERPOPARD, E_AMAZON, E_VALKYRIE], JOTUNN),
    ("Hall of Radiance", [SCARAB, E_MEDUSA, E_VALKYRIE], E_VALKYRIE),
    ("Hall of Shadows",  [E_DRAUGR, E_MINOTAUR, SHABTI], AMMIT),
]

def hall_floor(hall, floor):
    _, roster, boss = hall
    level = 20 + floor * 8
    stars = min(6, 3 + floor)
    difficulty = 0.75 + floor * 0.10
    spec = [(roster[(floor + slot) % len(roster)], level, stars, difficulty) for slot in range(3)]
    spec.append((boss, level, max(stars, boss.stars), difficulty * 1.4))
    return spec

def report_halls(trials=80):
    print("\nHALLS OF ESSENCE — win rate per floor over %d seeded battles" % trials)
    print("target: B1 for a levelled 4* team, B3 for 5*s with relics, B5 for a maxed 6* team\n")
    print(f"{'floor':>22}{'lvl':>5}  " + "".join(f"{n:>22}" for n, _ in CHAPTER_LADDERS))
    for hall in HALLS:
        for floor in (1, 3, 5):
            spec = hall_floor(hall, floor)
            row = f"{hall[0] + f' B{floor}':>22}{spec[0][1]:>5}  "
            for _, team in CHAPTER_LADDERS:
                wr, med = winrate(team, spec, trials=trials)
                row += f"{wr*100:>16.0f}% {med:>3.0f}t"
            print(row)

# The Labyrinth's relic dungeons, mirroring DungeonDatabase.labyrinth: ten
# levels, each three waves — two of three mobs, then the boss at x1.6 with two
# more — at level 10 + 4L, grade min(6, 3 + (L-1)//3), difficulty 0.70 + 0.08L.
# The team carries its health and cooldowns from wave to wave, which is what
# makes a run harder than its last wave alone.
LABYRINTHS = [  # name, roster, boss
    ("Vault of the Colossus",          [SENTINEL, SHABTI, SCARAB], COLOSSUS),
    ("Lair of the Hydra",              [E_MEDUSA, SERPOPARD, E_AMAZON], HYDRA),
    ("Necropolis of the Unwrapped King", [SHABTI, AMMIT, SERPOPARD], UNWRAPPED),
]

def labyrinth_grade(level):
    return min(6, 3 + (level - 1) // 3)

def labyrinth_waves(lab, level):
    _, roster, boss = lab
    enemy_level = 10 + level * 4
    stars = labyrinth_grade(level)
    difficulty = 0.70 + level * 0.08
    def wave(offset):
        return [(roster[(level + offset + slot) % len(roster)], enemy_level, stars, difficulty) for slot in range(3)]
    boss_wave = [(boss, enemy_level, max(stars, boss.stars), difficulty * 1.6)] + wave(2)[:2]
    return [wave(0), wave(1), boss_wave]

def winrate_waves(team_spec, waves, trials=60):
    """A run: the same fighters through every wave, wounds and cooldowns kept."""
    wins, lens = 0, []
    for s in range(trials):
        team = [mk(*t) for t in team_spec]
        total, result = 0, "a"
        for w, spec in enumerate(waves):
            result, turns = simulate(team, build_stage(spec), seed=s * 7 + w)
            total += turns
            if result != "a": break
        if result == "a": wins += 1
        lens.append(total)
    return wins / trials, statistics.median(lens)

LABYRINTH_LADDERS = [("4x 3* lv20", [(ANUBIS, 20, 3, 1.0)] * 4)] + CHAPTER_LADDERS

def report_labyrinths(trials=60):
    print("\nTHE LABYRINTH — win rate per level over %d seeded runs of three waves" % trials)
    print("target: B1 for a levelled 3* team out of chapter one, B4 for 4*s, B7 for 5*s with relics, B10 for maxed 6*s\n")
    print(f"{'level':>34}{'lvl':>5}  " + "".join(f"{n:>22}" for n, _ in LABYRINTH_LADDERS))
    for lab in LABYRINTHS:
        for level in (1, 4, 7, 10):
            waves = labyrinth_waves(lab, level)
            row = f"{lab[0] + f' B{level}':>34}{waves[0][0][1]:>5}  "
            for _, team in LABYRINTH_LADDERS:
                wr, med = winrate_waves(team, waves, trials=trials)
                row += f"{wr*100:>16.0f}% {med:>3.0f}t"
            print(row)

# The Endless Tower, mirroring DungeonDatabase's tower section: a hundred
# floors of ONE battle each, three mobs on an ordinary floor and a warden with
# two adds on every tenth. Progress is a high-water mark, so a floor is fought
# once and the curve has to be a ladder rather than a grind — that is why the
# level, the grade and the multiplier all climb at once and why the report
# below reads the milestone floors rather than a sample of the hundred.
#
# The five tiers are cycled twice, ten floors each: the same five wardens
# again at fifty floors' more difficulty. The rosters were levelled against
# each other (about 1,200 points of base health per tier) so that the climb
# rises with the curve and not with which tier a floor happens to land in;
# the Coil is a little the hardest of the five, which is why it holds floors
# 41-50 and 91-100, the two milestone walls.
TOWER_FLOORS = 100
TOWER_MILESTONES = (10, 25, 50, 75, 100)
TOWER_TIERS = [  # name, roster, warden
    ("Sand Stair",     [SENTINEL, form(FAMILIES["horus"], "radiance"), SCARAB], COLOSSUS),
    ("Marsh Landing",  [form(HERACLES, "tide"), form(HOPLITE, "radiance"),
                        form(HARPY, "tide")], HYDRA),
    ("Frozen Gallery", [form(FAMILIES["heimdall"], "tide"), E_TROLL, E_VALKYRIE], JOTUNN),
    ("Weighing Floor", [AMMIT, form(SEKHMET, "umbra"), SHABTI3_DARK], UNWRAPPED),
    ("The Coil",       [ANUBIS_DARK, ARES, ZEUS], APEP),
]

def tower_level(floor):      return 20 + floor // 2          # 20 at the door, 70 at the top
def tower_grade(floor):      return min(6, 3 + (floor - 1) // 20)
def tower_difficulty(floor): return 0.80 + floor * 0.011     # 0.81 -> 1.90
def tower_is_boss(floor):    return floor % 10 == 0
def tower_tier(floor):       return TOWER_TIERS[((floor - 1) // 10) % len(TOWER_TIERS)]

def tower_floor(floor):
    _, roster, warden = tower_tier(floor)
    level, stars, diff = tower_level(floor), tower_grade(floor), tower_difficulty(floor)
    mobs = [(roster[(floor + s) % len(roster)], level, stars, diff) for s in range(3)]
    if tower_is_boss(floor):
        # x1.8 rather than the Labyrinth's x1.6: a warden stands with two adds
        # instead of three, so the multiplier has to carry the missing body.
        return [(warden, level, max(stars, warden.stars), diff * 1.8)] + mobs[:2]
    return mobs

def tower_scroll(floor):
    if not tower_is_boss(floor): return None
    return "divine" if floor >= 80 else "pantheon" if floor >= 40 else "mystical"

def tower_rewards(floor):
    """Drachma, divinity, the relic grade on every fifth floor and the scroll
    on every tenth — DungeonDatabase.towerFloor's StageRewards."""
    return (800 + floor * 200,
            40 if tower_is_boss(floor) else 10,
            tower_grade(floor) if floor % 5 == 0 else None,
            tower_scroll(floor))

TOWER_MILESTONE_REWARDS = {   # DungeonDatabase.towerMilestoneReward
    10:  "150 divinity, 2 mystical, 20k drachma",
    25:  "300 divinity, 2 pantheon, a 4* relic",
    50:  "600 divinity, 1 divine, a 5* relic, 100k drachma",
    75:  "900 divinity, 2 divine, a 6* relic",
    100: "1500 divinity, 3 divine, two 6* relics",
}

def report_tower(trials=60):
    print("\nTHE ENDLESS TOWER — the floor curve")
    print("a floor is fought once: the high-water mark is the progress, so every floor is a gate\n")
    print(f"{'floor':>6}{'tier':>17}{'lvl':>5}{'grade':>7}{'x':>6}{'foes':>6}{'nrg':>5}"
          f"{'drachma':>10}{'div':>5}{'relic':>7}{'scroll':>10}   milestone")
    for floor in (1, 5, 10, 20, 25, 40, 50, 60, 75, 80, 90, 100):
        spec = tower_floor(floor)
        drachma, divinity, relic, scroll = tower_rewards(floor)
        name = tower_tier(floor)[0]
        foes = f"{len(spec)}{'+W' if tower_is_boss(floor) else ''}"
        print(f"{floor:>6}{name:>17}{tower_level(floor):>5}{tower_grade(floor):>6}*"
              f"{tower_difficulty(floor):>6.2f}{foes:>6}{6 + floor // 20:>5}"
              f"{drachma:>10,}{divinity:>5}{(str(relic) + '*') if relic else '-':>7}"
              f"{scroll or '-':>10}   {TOWER_MILESTONE_REWARDS.get(floor, '')}")

    print("\nTHE ENDLESS TOWER — win rate at the milestone floors over %d seeded battles" % trials)
    print("target: F1 for the team that just cleared the campaign, F10 for 4*s, F25 for 4*s with a\n"
          "grade in hand, F50 for 5*s with relics, F75 for maxed 6*s, F100 for a maxed god team —\n"
          "and F100 is meant to be a coin flip, not a certainty\n")
    print(f"{'floor':>22}{'lvl':>5}  " + "".join(f"{n:>22}" for n, _ in LABYRINTH_LADDERS))
    for floor in (1,) + TOWER_MILESTONES:
        spec = tower_floor(floor)
        row = f"{f'F{floor} ' + tower_tier(floor)[0]:>22}{tower_level(floor):>5}  "
        for _, team in LABYRINTH_LADDERS:
            wr, med = winrate(team, spec, trials=trials)
            row += f"{wr*100:>16.0f}% {med:>3.0f}t"
        print(row)

# ---------------------------------------------------------------------------
# Raids
# ---------------------------------------------------------------------------
#
# The raid bosses were tuned against a throwaway probe and the numbers were
# never mirrored here, which breaks the one rule this file exists for: a
# tuning constant that lives in Swift lives here too. These are the values in
# StageDatabase.swift's two `RaidBossProfile`s, and the simulation below is
# the ordinary engine with four things bolted on, because a raid is exactly
# the ordinary fight plus those four things.
#
# WHAT IS MODELLED, and what each one is FOR:
#   barrier    a pool in front of the health that eats damage first and stuns
#              the boss for a turn when it breaks, then comes back full after
#              N of the boss's turns. It is the fight's rhythm: burst it off,
#              take the free window, hit the health, do it again.
#   guard      minions topped back up to their full number every N boss
#              turns, each living one healing the boss a share of its max
#              health at the start of every boss turn. This is the reason to
#              kill them, and the reason a pure single-target team stalls.
#   enrage     a damage multiplier that lands on a battle-turn clock and
#              compounds. It is the timer: past it the fight is unwinnable,
#              so it sets the length rather than the difficulty.
#   weakness   the boss is open to one element at a time, rotating every N of
#              its turns, and everything else is punished. This is what stops
#              a raid being farmed by five copies of one god.
#
# WHAT IS NOT: the boss's own skill list is the generic kit the rest of this
# file gives a 6-star, so absolute clear times are indicative. What the report
# is for is the SHAPE — that an off-element team is punished, that ignoring
# the guard stalls the fight, and that the enrage turn arrives after a real
# team would have won and before a weak one could.
RAIDS = [
    # id, boss, level, stars, mult, adds(spawn, level, stars, mult, count),
    # barrier(frac, regen, stun), guard(interval, drain),
    # enrage(turn, mult, interval), weakness(elements, interval, on, off)
    ("The Serpent That Swallows the Sun", APEP, 60, 6, 2.0,
     (SCARAB, 55, 5, 1.1, 2), (0.12, 5, 1), (4, 0.022), (65, 1.8, 12),
     (["tide", "gale", "umbra"], 3, 1.7, 0.75), 36_000),
    ("The King Under the Ice", JOTUNN, 60, 6, 1.85,
     (E_TROLL, 55, 5, 0.8, 2), (0.14, 5, 1), (6, 0.035), (60, 1.9, 10),
     (["ember", "radiance"], 2, 1.7, 0.75), 45_000),
    # The three Titans that stood in the Labyrinth (phase 3): the guard's
    # raid, the shell's raid and the clock's raid.
    ("The Marsh That Grows Back", HYDRA, 60, 6, 1.9,
     (SERPOPARD, 55, 5, 1.0, 2), (0.10, 4, 1), (3, 0.03), (80, 1.7, 12),
     (["gale", "radiance", "umbra"], 3, 1.7, 0.75), 40_000),
    ("The Statue That Stood Up", COLOSSUS, 60, 6, 1.8,
     (SENTINEL, 55, 5, 0.9, 2), (0.16, 6, 2), (5, 0.03), (82, 1.8, 12),
     (["umbra", "tide"], 2, 1.7, 0.75), 48_000),
    ("The King Who Was Never Weighed", UNWRAPPED, 60, 6, 1.85,
     (E_DRAUGR, 55, 5, 0.9, 2), (0.08, 3, 1), (3, 0.025), (55, 1.9, 10),
     (["radiance", "ember"], 2, 1.7, 0.75), 42_000),
]

def simulate_raid(team_spec, raid, seed=0, kill_adds=True, boon=None, stats=None):
    """One raid. Returns ("a"|"b"|"draw", battle turns, boss turns, share).

    `kill_adds=False` models a team that ignores the guard, which is the
    comparison the drain number exists to lose. `boon` goes in every socket
    of the team and `stats` collects the team's damage dealt, taken and
    healed, for `--boons`.
    """
    (_, bossbp, blvl, bstars, bmult, add, barrier, guard, enrage, weak, _) = raid
    addbp, addlvl, addstars, addmult, addcount = add
    bfrac, bregen, bstun = barrier
    ginterval, gdrain = guard
    eturn, emult, einterval = enrage
    welems, winterval, won, woff = weak

    rng = random.Random(seed)
    team = [mk(*t) for t in team_spec]
    for f in team: f.boon = boon
    boss = mk(bossbp, blvl, bstars, 1.0, bmult)
    adds = [mk(addbp, addlvl, addstars, 1.0, addmult) for _ in range(addcount)]
    def note(key, side, amount):
        if stats is not None and amount:
            stats[key][side] = stats[key].get(side, 0.0) + amount

    pool = boss.maxhp * bfrac
    shield, regen_left = pool, 0
    boss_turns, wi, stunned = 0, 0, 0
    turns = 0
    for f in team: f.side = "a"
    for f in [boss] + adds: f.side = "b"
    boon_battle_start(team)

    # The share of the boss's health taken, BattleResult.raidShare: what
    # grades a run the boss survived. The barrier soaks in front of the
    # health and is not counted.
    share = lambda: 1.0 if not boss.alive else 1.0 - max(0.0, boss.hp) / boss.maxhp
    while turns < MAX_TURNS:
        foes = [f for f in [boss] + adds if f.alive]
        if not [f for f in team if f.alive]: return "b", turns, boss_turns, share()
        if not boss.alive: return "a", turns, boss_turns, 1.0
        alive = [f for f in team if f.alive] + foes
        step = min((1.0 - f.atb) / max(1e-6, f.spd * ATB_RATE) for f in alive)
        for f in alive: f.atb = min(1.0, f.atb + f.spd * ATB_RATE * step)
        actor = max((f for f in alive if f.atb >= 1 - 1e-9),
                    key=lambda f: (f.spd, -f.seq), default=None)
        if actor is None: continue
        actor.atb = 0.0
        turns += 1
        for i in range(len(actor.cds)):
            actor.cds[i] = max(0, actor.cds[i] - 1)

        if actor.side == "b":
            if actor is boss:
                boss_turns += 1
                # The barrier's regeneration clock runs whether the boss acts
                # or not — BattleEngine is explicit that letting the stun stop
                # it would mean the window paid for itself twice.
                if shield <= 0:
                    regen_left -= 1
                    if regen_left <= 0:
                        shield = pool
                # Everything else is something the boss DOES, so a turn lost
                # to the stun costs it the drain, the summon and the rotation.
                if stunned > 0:
                    stunned -= 1
                    continue
                # The guard drains first and is topped back up after, so a
                # minion summoned this turn does not also heal on it.
                living = [a for a in adds if a.alive]
                if living:
                    boss.hp = min(boss.maxhp, boss.hp + boss.maxhp * gdrain * len(living))
                if ginterval and boss_turns % ginterval == 0:
                    for a in adds:
                        if not a.alive:
                            a.hp = a.maxhp
                if winterval and boss_turns % winterval == 0:
                    wi = (wi + 1) % max(1, len(welems))
            # Enrage is a BATTLE-turn clock, not the boss's, so a fast team
            # meets it sooner in its own turns and later in the boss's.
            factor = 1.0
            if eturn and turns >= eturn:
                stacks = 1 + ((turns - eturn) // einterval if einterval else 0)
                factor = emult ** stacks
            live_team = [f for f in team if f.alive]
            if not live_team: continue
            target = min(live_team, key=lambda f: f.hp)
            name, mult, hits, cd, defign, missbonus, aoe = actor.bp.skills[0]
            for _ in range(hits):
                dmg = resolve_hit(actor, target, mult * factor, defign, missbonus, rng)
                note("taken", "a", land(target, dmg))
            continue

        # A player turn. Adds first when the team is playing properly, because
        # a living guard is healing the boss faster than most teams can hurt it.
        opened = boon_turn_start(actor)
        note("healed", "a", opened); note("boonHealed", "a", opened)
        live_adds = [a for a in adds if a.alive]
        victim = live_adds[0] if (kill_adds and live_adds) else boss
        ready = [i for i, s in enumerate(actor.bp.skills) if actor.cds[i] == 0
                 and actor.bp.skills[i][1] > 0]
        if not ready:
            actor.acted = True
            continue
        idx = max(ready, key=lambda i: actor.bp.skills[i][1] * actor.bp.skills[i][2])
        name, mult, hits, cd, defign, missbonus, aoe = actor.bp.skills[idx]
        actor.cds[idx] = cd
        # The element that is up multiplies; everything else is punished. This
        # is the raid's own wheel and it replaces the ordinary one.
        up = welems[wi] if welems else None
        ratio = won if (up and actor.bp.element == up) else woff
        dealt = 0.0
        for _ in range(hits):
            if not victim.alive:
                live_adds = [a for a in adds if a.alive]
                victim = live_adds[0] if (kill_adds and live_adds) else boss
            dmg = resolve_hit(actor, victim, mult, defign, missbonus, rng) * ratio
            if victim is boss and shield > 0:
                shield -= dmg
                if shield <= 0:
                    # Breaking it stuns straight, not against resistance, and
                    # the overflow is lost: the reward is the free window.
                    shield, regen_left, stunned = 0, bregen, bstun
                continue
            # What lands on health is what is dealt; the barrier is not the
            # health, so Hydra's Blood recovers nothing off it.
            applied = land(victim, dmg)
            dealt += applied
            note("dealt", "a", applied)
        drunk = boon_after_hit(actor, dealt)
        note("healed", "a", drunk); note("boonHealed", "a", drunk)
        actor.acted = True
    return "draw", turns, boss_turns, share()

def raid_result(team_spec, raid, trials=40, kill_adds=True):
    wins, lens = 0, []
    for s in range(trials):
        r, turns, _, _ = simulate_raid(team_spec, raid, seed=s, kill_adds=kill_adds)
        if r == "a": wins += 1
        lens.append(turns)
    return wins / trials, statistics.median(lens)

# The raid's ladders, one unit on each element the boss opens to: what a
# player brings to a raid, and what both raid reports measure.
def raid_ladders(welems):
    onel = (welems * 4)[:4]
    return [
        # Stand-ins on the family's numbers (`replace`, not `form`): "a unit
        # on each element", not four premium Anubis.
        ("built for it, 6* max",    [(replace(ANUBIS, element=e), 60, 6, 1.55) for e in onel]),
        ("built for it, 6* lv55",   [(replace(ANUBIS, element=e), 55, 6, 1.30) for e in onel]),
        ("built for it, 5* +relic", [(replace(ANUBIS, element=e), 45, 5, 1.15) for e in onel]),
        ("wrong element, 6* max",   [(replace(ANUBIS, element=(
            "ember" if "ember" not in welems else "tide")), 60, 6, 1.55)] * 4),
    ]

# ---------------------------------------------------------------------------
# The raid grade — Pantheon/Core/PvE/RaidGradeService.swift, mirrored.
#
# A kill is graded on its PACE against the boss's enrage turn; a run the boss
# survived on the SHARE of its health the team took. The two never overlap: a
# kill is B at worst and a non-kill C at best. Change a number in both files.
GRADES = ["f", "d", "c", "b", "a", "s", "ss", "sss"]
GRADE_PACE  = [("sss", 0.70), ("ss", 0.85), ("s", 1.00), ("a", 1.30)]   # kill inside this x enrageTurn, else "b"
GRADE_SHARE = [("c", 0.60), ("d", 0.30)]                                # boss survived: share taken >= this, else "f"
DEFAULT_ENRAGE = 60                                                      # a profile with no clock
AETHER_BY_GRADE = {"f": (0, 0), "d": (2, 0), "c": (4, 0), "b": (5, 1), "a": (6, 1),
                   "s": (8, 2), "ss": (10, 3), "sss": (12, 4)}          # (elemental, pure) per run
GRADE_QUALITY_FLOOR = {"s": "hero", "ss": "hero", "sss": "legend"}      # the raid's relic; Rare below
# What one relic awakening costs (RelicService.awakening*): the set's own
# colour at the fair price, any other at half again, and the pure kind.
AWAKENING_COST = {"matching": 60, "other": 90, "pure": 15}
AWAKENING_AETHER = (AWAKENING_COST["matching"], AWAKENING_COST["pure"])
RAID_ENERGY = 12

def turns_allowed(grade, enrage_turn):
    """RaidGradeService.turnsAllowed: the last turn a kill earns the grade on."""
    frac = dict(GRADE_PACE).get(grade)
    if frac is None: return None
    return math.floor((enrage_turn or DEFAULT_ENRAGE) * frac + 1e-9)

def raid_grade(outcome, turns, share, enrage_turn):
    if outcome == "a":
        for g, _ in GRADE_PACE:
            if max(1, turns) <= turns_allowed(g, enrage_turn): return g
        return "b"
    for g, frac in GRADE_SHARE:
        if share >= frac: return g
    return "f"

def runs_per_awakening(elemental, pure):
    """Raids at a steady per-run payout until one awakening is afforded; None
    when the payout has no pure aether in it, which no number of runs fixes."""
    need_e, need_p = AWAKENING_AETHER
    if pure <= 0 or elemental <= 0: return None
    return max(math.ceil(need_e / elemental), math.ceil(need_p / pure))

def report_grades(trials=40):
    print("\nRAID GRADES — F to SSS, and the Aether each pays")
    print("a kill is graded on its PACE against the boss's enrage turn: SSS inside 70% of it, SS 85%,")
    print("S 100% (before it enrages), A 130%, any kill a B. A run the boss survived is graded on the")
    print("SHARE of its health taken: C from 60%, D from 30%, else F — never a B, so a kill always")
    print("outranks a non-kill. Total damage cannot grade a kill here: the barrier regenerates and")
    print("the guard heals, so a SLOW kill deals MORE damage than a fast one and the ladder would")
    print("run backwards.\n")
    print("  aether per run (elemental+pure):  " + "  ".join(
        f"{g.upper()} {e}+{p}" for g, (e, p) in AETHER_BY_GRADE.items()))
    print(f"  one awakening (phase 2, planned): {AWAKENING_AETHER[0]} elemental + {AWAKENING_AETHER[1]} pure")
    print("  runs to one at a steady grade:    " + "  ".join(
        f"{g.upper()} {runs_per_awakening(e, p) or '—'}" for g, (e, p) in AETHER_BY_GRADE.items()))
    print("  relic quality floor: " + ", ".join(
        f"{g.upper()} {q}" for g, q in GRADE_QUALITY_FLOOR.items()) + "; Rare below\n")

    # The shape, asserted, whatever the numbers are.
    for g in GRADES:
        e, p = AETHER_BY_GRADE[g]
        is_kill = GRADES.index(g) >= GRADES.index("b")
        assert (p > 0) == is_kill, f"{g}: pure aether comes from a kill and only a kill"
    assert AETHER_BY_GRADE["f"] == (0, 0), "an F pays nothing, so a forfeit farms nothing"
    for lo, hi in zip(GRADES, GRADES[1:]):
        assert AETHER_BY_GRADE[lo] <= AETHER_BY_GRADE[hi], f"aether must climb from {lo} to {hi}"
    assert raid_grade("a", MAX_TURNS, 1.0, 65) == "b", "the slowest kill is still a B"
    assert raid_grade("b", 1, 1.0, 65) == "c", "the best non-kill is a C"
    assert GRADES.index(raid_grade("a", MAX_TURNS, 1.0, 65)) > GRADES.index(raid_grade("b", 1, 1.0, 65)), \
        "a kill outranks a non-kill"
    assert runs_per_awakening(*AETHER_BY_GRADE["sss"]) >= 4, "even SSS runs take days, not an afternoon"

    for raid in RAIDS:
        (name, _, lvl, stars, mult, add, barrier, guard, enrage, weak, power) = raid
        eturn = enrage[0]
        bars = ", ".join(f"{g.upper()} by turn {turns_allowed(g, eturn)}" for g, _ in GRADE_PACE)
        print(f"  {name}  (enrages on turn {eturn}: {bars})")
        for label, team in raid_ladders(weak[0]):
            dist = {g: 0 for g in GRADES}
            e_sum = p_sum = 0
            kills, shares = [], []
            for s in range(trials):
                r, turns, _, share = simulate_raid(team, raid, seed=s)
                g = raid_grade(r, turns, share, eturn)
                dist[g] += 1
                e, p = AETHER_BY_GRADE[g]
                e_sum += e
                p_sum += p
                (kills if r == "a" else shares).append(turns if r == "a" else share)
            e_avg, p_avg = e_sum / trials, p_sum / trials
            spread = " ".join(f"{g.upper()} {dist[g] * 100 / trials:.0f}%" for g in reversed(GRADES) if dist[g])
            runs = runs_per_awakening(e_avg, p_avg)
            per = f"an awakening every {runs} runs ({runs * RAID_ENERGY} energy)" if runs else "no pure aether: no awakening"
            how = (f"kills in {min(kills)}-{max(kills)}t, median {statistics.median(kills):.0f}" if kills else
                   f"takes {min(shares) * 100:.0f}-{max(shares) * 100:.0f}% of its health")
            print(f"      {label:>24}  {spread:<30} {e_avg:4.1f}+{p_avg:3.1f}/run  {per}")
            print(f"      {'':>24}  {how}")
        print()
    print("  → intended: the best ladder team (a maxed 6* four with no sets, no skill-ups, no leader)")
    print("    sits on the S/A line of the serpent — its median kill IS the enrage turn, which is how")
    print("    the enrage was tuned — and at A on the Jötunn, the harder raid. SS wants about a fifth")
    print("    more pace than that team has and SSS a third: the sets, the skill-ups, a leader and a")
    print("    fifth unit, none of which the sim has. The lv55 team farms C/B; a 5* team cannot get")
    print("    through the barrier and is told so by an F, which is the raid's power line doing its job.")

def report_raids(trials=40):
    print("\nRAIDS — the two boss encounters")
    print("a raid is the ordinary fight plus four things: a barrier that stuns when it breaks, a\n"
          "guard that heals the boss while it lives, an enrage on a battle-turn clock, and a\n"
          "weakness that rotates. The shape is the point, not the absolute clear time.\n")
    for raid in RAIDS:
        (name, _, lvl, stars, mult, add, barrier, guard, enrage, weak, power) = raid
        bfrac, bregen, bstun = barrier
        ginterval, gdrain = guard
        eturn, emult, einterval = enrage
        welems, winterval, won, woff = weak
        print(f"  {name}")
        print(f"    boss lv{lvl} {stars}* x{mult}   recommended power {power:,}")
        print(f"    barrier  {bfrac*100:.0f}% of its health, back after {bregen} boss turns, "
              f"breaking stuns {bstun}")
        print(f"    guard    {add[4]} x lv{add[1]} {add[2]}*, topped up every {ginterval} boss turns, "
              f"each heals it {gdrain*100:.1f}%/turn")
        print(f"    enrage   x{emult} from battle turn {eturn}, again every {einterval}")
        print(f"    opens to {', '.join(welems)} every {winterval} boss turns "
              f"(x{won} on element, x{woff} off)")
        # The ladders here are built FOR the boss, one unit on each element it
        # opens to, because that is what a player brings to a raid and because
        # measuring a mono-element team against a rotating weakness measures
        # the punishment rather than the fight. The wrong-element row is kept
        # to show that the punishment is real.
        for label, team in raid_ladders(welems):
            wr, med = raid_result(team, raid, trials=trials)
            wrx, _ = raid_result(team, raid, trials=trials, kill_adds=False)
            print(f"      {label:>24}  kill the guard {wr*100:>4.0f}% in {med:>4.0f}t   "
                  f"ignore it {wrx*100:>4.0f}%")
        print()


# ---------------------------------------------------------------------------
# Relic awakening — phase 2 of the Titans (Relic.awakened, RelicService.awaken).
#
# A FLAG on a 6★, not a grade above it: a FIFTH sub stat (the cap is four
# everywhere else), the +15 main stat at 3.6x instead of 3x, a halo. Done to
# a 6★ +15 for aether, or dropped so from the hardest content. The one thing
# this report exists to assert is that a well-rolled ordinary 6★ still beats
# a badly-rolled awakened one — the flag is a step, not a new tier that makes
# every 6★ in the bag junk.
SET_AETHER = {"fury": "ember", "ichor": "ember", "wrath": "ember", "titanfall": "ember",
              "aegis": "tide", "styx": "tide", "wards": "tide",
              "bulwark": "gale", "zephyr": "gale", "chains": "gale",
              "thunder": "radiance", "fates": "radiance", "vigil": "radiance",
              "ruin": "umbra", "oracle": "umbra", "nemesis": "umbra"}      # RelicSet.aetherElement
SUB_CAP, AWAKENED_SUB_CAP = 4, 5                                           # Relic.subStatCap
MAIN_PEAK, AWAKENED_MAIN_PEAK = 3.0, 3.6                                    # Relic.peak / awakenedPeak
AWAKENED_DROP = {"raid SS": 0.08, "raid SSS": 0.15,                         # RaidGradeService.awakenedChance
                 "Labyrinth B10": 0.04,                                     # DungeonDatabase.labyrinthAwakenedChance
                 "Endless Tower F90+ (relic floors)": 0.06,                 # towerAwakenedChance
                 "Hell, chapter 7 on": 0.02}                                # CampaignDifficulty.hellAwakenedChance
MAIN_STAT_BASE = {"critdmg": 0.05, "atk%": 0.05, "hp%": 0.05, "def%": 0.05, "spd": 5,
                  "crit": 0.04, "acc": 0.04, "res": 0.04, "atk": 12, "def": 12, "hp": 180}
MAIN_GRADE_SCALE = 0.32                                                     # RelicService.mainStatValue
# RelicService.weight(for: .attacker) and normalized(): the score the
# optimiser and the auto-equip use, so "better" here is the game's own word.
ATTACKER_WEIGHT = {"atk%": 1.4, "atk": 1.4, "crit": 1.6, "critdmg": 1.5, "spd": 1.3}
SUB_KINDS = ["hp", "hp%", "atk", "atk%", "def", "def%", "spd", "crit", "critdmg", "acc", "res"]

def main_stat_base(kind, grade=6):
    return MAIN_STAT_BASE[kind] * (1 + (grade - 1) * MAIN_GRADE_SCALE)

def normalized_stat(kind, value):
    if kind == "hp": return value / 180
    if kind in ("atk", "def"): return value / 12
    if kind == "spd": return value / 2
    return value * 100 / 5

def attacker_weight(kind):
    return ATTACKER_WEIGHT.get(kind, 0.3)

def relic_score(main_kind, main_mult, subs):
    """subs: [(kind, value)]. The attacker's score of a slot-4 relic."""
    score = attacker_weight(main_kind) * normalized_stat(main_kind, main_stat_base(main_kind) * main_mult)
    for kind, value in subs:
        score += attacker_weight(kind) * normalized_stat(kind, value)
    return score

def report_awakening(trials=20_000):
    import random as _r
    print("\nRELIC AWAKENING — the tier above 6*, as a flag")
    print("a 6* at +15 awakens for aether: a FIFTH sub stat (chosen from two, like every roll),")
    print(f"the +15 main stat at {AWAKENED_MAIN_PEAK}x instead of {MAIN_PEAK}x, a halo. Or it drops that way.\n")
    print(f"  cost: {AWAKENING_COST['matching']} aether of the set's own colour, or {AWAKENING_COST['other']} of any other, "
          f"plus {AWAKENING_COST['pure']} pure")
    by_element = {}
    for s, e in SET_AETHER.items(): by_element.setdefault(e, []).append(s)
    for element, sets in by_element.items():
        print(f"    {element:>9}: {', '.join(sets)}")
    print("  awakened drops: " + ", ".join(f"{k} {v*100:.0f}%" for k, v in AWAKENED_DROP.items()))
    print(f"    → a raid at SSS every {1 / AWAKENED_DROP['raid SSS']:.0f} kills ({RAID_ENERGY / AWAKENED_DROP['raid SSS']:.0f} energy), "
          f"the Labyrinth's B10 every {1 / AWAKENED_DROP['Labyrinth B10']:.0f} runs")

    # The comparison, in the game's own score for an attacker on a slot-4
    # relic whose main stat is CRIT DMG.
    main = "critdmg"
    pool = [k for k in SUB_KINDS if k != main]
    best_kinds = sorted(pool, key=lambda k: -attacker_weight(k) * normalized_stat(k, sub_stat_base(k)))
    worst_kinds = list(reversed(best_kinds))
    top = best_kinds[:SUB_CAP]
    well = [(k, sub_stat_base(k) * 1.25) for k in top]
    well[0] = (well[0][0], well[0][1] + 4 * sub_stat_base(well[0][0]) * 1.25)      # four grows on the best
    well_ordinary = relic_score(main, MAIN_PEAK, well)
    bad = [(k, sub_stat_base(k) * 0.75) for k in worst_kinds[:AWAKENED_SUB_CAP]]
    bad[0] = (bad[0][0], bad[0][1] + 4 * sub_stat_base(bad[0][0]) * 0.75)          # four grows on the worst
    bad_awakened = relic_score(main, AWAKENED_MAIN_PEAK, bad)
    print(f"\n  a well-rolled ordinary 6* +15 (the best four kinds at the top of the range, the")
    print(f"  best of them grown four times) scores {well_ordinary:6.1f}")
    print(f"  a badly-rolled AWAKENED 6* +15 (the worst five kinds at the bottom, the worst")
    print(f"  of them grown four times, the main at {AWAKENED_MAIN_PEAK}x) scores {bad_awakened:6.1f}")
    verdict = "the flag is a step, not a tier: rolls still decide" if well_ordinary > bad_awakened else \
        "AN AWAKENING BEATS EVERY ROLL — the ceiling or the fifth sub is too big"
    print(f"  → {verdict}")
    assert well_ordinary > bad_awakened, verdict

    # And on average: the same relic, rolled at random, with and without.
    rng = _r.Random(20260916)
    def mean_score(cap, main_mult):
        total = 0.0
        for _ in range(trials):
            kinds = rng.sample(pool, cap)
            subs = [(k, sub_stat_base(k) * rng.uniform(0.75, 1.25)) for k in kinds]
            for _ in range(4):
                i = rng.randrange(cap)
                k, v = subs[i]
                subs[i] = (k, v + sub_stat_base(k) * rng.uniform(0.75, 1.25))
            total += relic_score(main, main_mult, subs)
        return total / trials
    ordinary = mean_score(SUB_CAP, MAIN_PEAK)
    awakened = mean_score(AWAKENED_SUB_CAP, AWAKENED_MAIN_PEAK)
    lift = awakened / ordinary
    print(f"\n  rolled at random, {trials:,} times each: an ordinary +15 averages {ordinary:.1f}, an awakened")
    print(f"  one {awakened:.1f} — {lift:.2f}x, the awakening's premium")
    assert 1.05 < lift < 1.40, f"the premium is {lift:.2f}x: under 1.05 nobody bothers, over 1.40 it is a new tier"
    print("  → intended: between 1.05x and 1.40x — worth a week of raids, and still a relic a")
    print("    good roll on an ordinary 6* can beat")


# ---------------------------------------------------------------------------
# Boons — Core/Models/Boon.swift, Core/Progression/BoonService.swift and the
# four hooks in BattleEngine, mirrored. A boon is measured by what it DOES to
# a fight the sim already plays: with the kind in every socket of the team
# against without, on the same seeds. An offensive kind is read off damage
# dealt per battle turn (the total dealt in a WIN is the foes' health and
# cannot rise, so the pace is the number); a defensive kind off the net
# damage taken per turn — taken less healed. The rule (Docs/PLAN.md, *Boons*)
# is Epic Seven's lesson: every kind's BEST fight lifts 6-18% at 6*, and no
# kind is the best on more than two of the five fights.
# ---------------------------------------------------------------------------

def boon_tally(stats_list, turns_list, wins, trials):
    """Per-turn figures over a batch of runs: damage dealt, damage taken and
    what the boon itself healed, plus the win rate and the length."""
    dealt = sum(s["dealt"].get("a", 0.0) for s in stats_list)
    taken = sum(s["taken"].get("a", 0.0) for s in stats_list)
    healed = sum(s["boonHealed"].get("a", 0.0) for s in stats_list)
    turns = max(1.0, float(sum(turns_list)))
    return {"dps": dealt / turns, "taken": taken / turns, "boonHealed": healed / turns,
            "wins": wins / trials, "turns": turns / trials}

def boon_run(team_spec, waves, boon, trials):
    """A run of waves with `boon` in every socket of the team."""
    stats_list, turns_list, wins = [], [], 0
    for s in range(trials):
        team = [mk(*t) for t in team_spec]
        for f in team: f.boon = boon
        stats = {"dealt": {}, "taken": {}, "healed": {}, "boonHealed": {}}
        result, total = "a", 0
        for w, spec in enumerate(waves):
            result, t = simulate(team, build_stage(spec), seed=s * 7 + w, stats=stats, first_wave=(w == 0))
            total += t
            if result != "a": break
        if result == "a": wins += 1
        stats_list.append(stats); turns_list.append(total)
    return boon_tally(stats_list, turns_list, wins, trials)

def boon_raid_run(team_spec, raid, boon, trials):
    stats_list, turns_list, wins = [], [], 0
    for s in range(trials):
        stats = {"dealt": {}, "taken": {}, "healed": {}, "boonHealed": {}}
        r, t, _, _ = simulate_raid(team_spec, raid, seed=s, boon=boon, stats=stats)
        if r == "a": wins += 1
        stats_list.append(stats); turns_list.append(t)
    return boon_tally(stats_list, turns_list, wins, trials)

def boon_lift(family, base, run):
    """What the kind is worth on a fight, against the same fight with no boon:
    an offensive kind (and Swift-footed) the rise in damage dealt per turn; a
    Ward the fall in damage taken per turn; a heal the share of the damage
    taken that the boon itself gave back. The sim's own heal AI (a 25% team
    heal whenever anyone is under 60%) swamps a net-damage figure, which is
    why the heals are read off their own number."""
    hook = BOONS[family][1]
    if hook == "damageTaken":
        return 1 - run["taken"] / base["taken"] if base["taken"] > 0 else 0.0
    if hook in ("turnStart", "afterHit"):
        return run["boonHealed"] / run["taken"] if run["taken"] > 0 else 0.0
    return run["dps"] / base["dps"] - 1 if base["dps"] > 0 else 0.0

def boon_fights():
    """The five fights every kind is measured on: a mono-element hall (the
    Banes' and the Wards' home), a three-wave chapter boss stage, the
    Labyrinth's last level, a Titan, and an arena fight of gods against
    gods. Each is (label, kind, team, spec)."""
    # Four maxed 6* units on the family's numbers: a line's lift is
    # calibrated on a generic team, and four premium copies is a team nobody
    # fields (the note at LIGHT_DARK_PREMIUM).
    six = [(ANUBIS, 55, 6, 1.60)] * 4
    # Four attackers and no heal between them: the arena's nuke team, the
    # fight where a unit is worn down rather than topped up.
    nukers = [(SEKHMET, 60, 6, 1.60), (ZEUS, 60, 6, 1.60), (PERSEUS, 60, 6, 1.60), (HARPY, 60, 6, 1.60)]
    # The enemy line in four colours, as an arena's is: the reference forms
    # are all ember, and a mono-ember mirror made a Bane of Ember a flat
    # +15% on everything, which no real arena team is. Stand-in colours on
    # the family's numbers (`replace`), the dark Harpy's included.
    foes = [(SEKHMET, 60, 6, 1.6), (replace(ZEUS, element="tide"), 60, 6, 1.6),
            (replace(PERSEUS, element="gale"), 60, 6, 1.6), (replace(HARPY, element="umbra"), 60, 6, 1.6)]
    colossus = RAIDS[3]
    return [
        ("Hall of Embers B5",         "waves", six,    [hall_floor(HALLS[0], 5)]),
        ("Olympus 3 boss stage",      "waves", six,    generated_waves(CHAPTERS[3], 10)[0]),
        ("Necropolis B10",            "waves", six,    labyrinth_waves(LABYRINTHS[2], 10)),
        ("The Statue That Stood Up",  "raid",  raid_ladders(colossus[9][0])[0][1], colossus),
        ("Arena, nukers vs nukers",   "waves", nukers, [foes]),
    ]

def boon_dominant_element(fight):
    """The colour a Bane or a Ward is measured in: the fight's most common."""
    _, kind, _, spec = fight
    if kind == "raid": return spec[1].element
    from collections import Counter
    return Counter(e[0].element for wave in spec for e in wave).most_common(1)[0][0]

def report_boons(trials=24):
    print("\nBOONS — the earned socket: each kind's lift on five fights, over %d seeded runs each" % trials)
    print("a boon is one CONDITIONAL line in the socket at the centre of the ring, chosen from a cache's three,")
    print("its size rolled %.2f-%.2fx the base and pushed up to %d times (+%.0f%% of the base a push, a choice of two)."
          % (BOON_ROLL[0], BOON_ROLL[1], BOON_PUSH["max"], BOON_PUSH["step"] * 100))
    print("an offensive kind is read off damage dealt per turn, a Ward off damage taken per turn, a heal off")
    print("the share of the damage taken that it gives back.")
    print("rule: every kind's BEST fight lifts 6-18% at 6*; no kind is the best on more than two of the five.\n")
    print("  sources: " + "; ".join(f"{k} {v[0]*100:.0f}% ({v[1]})" for k, v in BOON_SOURCES.items()))
    fights = boon_fights()
    families = list(BOONS)
    lifts = {}
    elements = {}
    for fight in fights:
        label, kind, team, spec = fight
        if kind == "raid":
            run = lambda b, team=team, spec=spec: boon_raid_run(team, spec, b, trials)
        else:
            run = lambda b, team=team, spec=spec: boon_run(team, spec, b, trials)
        base = run(None)
        element = boon_dominant_element(fight)
        elements[label] = element
        for fam in families:
            mag, _ = BOONS[fam]
            b = (fam, element if fam in ("bane", "ward") else None, mag)
            lifts[(fam, label)] = boon_lift(fam, base, run(b))
    labels = [f[0] for f in fights]
    print(f"\n  {'kind (6* base)':>22}" + "".join(f"{l[:22]:>24}" for l in labels) + f"{'best':>8}")
    print(f"  {'':>22}" + "".join(f"{('vs ' + elements[l]):>24}" for l in labels))
    best = {}
    for fam in families:
        row = f"  {fam + ' ' + str(BOONS[fam][0]):>22}"
        for l in labels:
            row += f"{lifts[(fam, l)] * 100:>23.1f}%"
        best[fam] = max(labels, key=lambda l: lifts[(fam, l)])
        row += f"{lifts[(fam, best[fam])] * 100:>7.1f}%"
        print(row)
    tops = {}
    for l in labels:
        top = max(families, key=lambda fam: lifts[(fam, l)])
        tops[top] = tops.get(top, 0) + 1
    print("\n  best on each fight: " + ", ".join(
        f"{l[:22]}: {max(families, key=lambda fam: lifts[(fam, l)])}" for l in labels))
    for fam in families:
        lift = lifts[(fam, best[fam])]
        verdict = "ok" if 0.06 <= lift <= 0.18 else ("NOBODY SOCKETS IT" if lift < 0.06 else "MANDATORY")
        print(f"    {fam:>12}: best {lift*100:5.1f}% on {best[fam]} — {verdict}")
        assert 0.06 <= lift <= 0.18, \
            f"{fam}'s best fight lifts {lift*100:.1f}%: under 6 nobody sockets it, over 18 it is mandatory"
    for fam, n in tops.items():
        assert n <= 2, f"{fam} is the best boon on {n} of the five fights: a kind that is best everywhere is Epic Seven's mistake"
    print("  → every kind has a fight it is worth 6-18% on, and none is the best on more than two")

# ---------------------------------------------------------------------------
# Pantheon resonance, measured the way the boons are: a mono team of the
# kind's pantheon at rank I and at rank II against the same fight with no
# resonance, on the same seeds. A damage kind is read off damage dealt per
# turn, the Legion off damage taken per turn, the Mandate off the share of
# the damage taken its Recovery gave back. Docs/PLAN.md, *Pantheon resonance*.
# ---------------------------------------------------------------------------

def resonance_run(team_spec, waves, kind, rank, trials):
    stats_list, turns_list, wins = [], [], 0
    for s in range(trials):
        team = [mk(*t) for t in team_spec]
        if kind: apply_resonance(team, kind, rank)
        stats = {"dealt": {}, "taken": {}, "healed": {}, "boonHealed": {}}
        result, total = "a", 0
        for w, spec in enumerate(waves):
            result, t = simulate(team, build_stage(spec), seed=s * 7 + w, stats=stats, first_wave=(w == 0))
            total += t
            if result != "a": break
        if result == "a": wins += 1
        stats_list.append(stats); turns_list.append(total)
    return boon_tally(stats_list, turns_list, wins, trials)

def resonance_lift(kind, rank, base, run):
    """A damage kind off damage dealt per turn; the Legion off damage taken
    per turn; the Mandate as the health it adds plus the share of the damage
    taken its Recovery gave back — more health IS taking less, per point."""
    if kind == "theLegion":
        return 1 - run["taken"] / base["taken"] if base["taken"] > 0 else 0.0
    if kind == "mandateOfHeaven":
        pool = RESONANCE[kind][rank].get("hp%", 0.0)
        return pool + (run["boonHealed"] / run["taken"] if run["taken"] > 0 else 0.0)
    return run["dps"] / base["dps"] - 1 if base["dps"] > 0 else 0.0

def resonance_fights():
    """Two fights of real lineups: four gods through a chapter's boss stage
    (a kit that debuffs, heals and loses a unit now and then) and the
    arena's nukers against a four-colour line. A resonance is a bonus the
    whole lineup carries everywhere, so it is read on the MEAN of the two."""
    gods = [(SEKHMET, 60, 6, 1.60), (ZEUS, 60, 6, 1.60), (ARES, 60, 6, 1.60), (ANUBIS, 60, 6, 1.60)]
    arena = next(f for f in boon_fights() if f[0].startswith("Arena"))
    return [("Olympus 3 boss stage, four gods", "waves", gods, generated_waves(CHAPTERS[3], 10)[0]), arena]

def resonance_table(trials=24):
    fights = resonance_fights()
    lifts = {}
    for label, _, team, spec in fights:
        base = resonance_run(team, spec, None, 0, trials)
        for kind in RESONANCE:
            for rank in (1, 2):
                if kind == "concord" and rank == 2: continue
                run = resonance_run(team, spec, kind, rank, trials)
                lifts[(kind, rank, label)] = resonance_lift(kind, rank, base, run)
    return [f[0] for f in fights], lifts

def report_resonance(trials=24):
    print("\nPANTHEON RESONANCE — each kind at rank I and II on two fights, over %d seeded runs each" % trials)
    print("a pair of one pantheon lights rank I, three or more rank II, four different pantheons the Concord;")
    print("a damage kind is read off damage dealt per turn, the Legion off damage taken, the Mandate as the")
    print("health it adds plus the share of the damage taken its Recovery gave back; each on the MEAN of the")
    print("two fights. rule: rank I 3-8%, rank II 8-16%, the Concord between.\n")
    labels, lifts = resonance_table(trials)
    print(f"  {'kind':>18} {'rank':>4}" + "".join(f"{l[:30]:>32}" for l in labels) + f"{'mean':>8}")
    misses = []
    for kind in RESONANCE:
        for rank in (1, 2):
            if kind == "concord" and rank == 2: continue
            row = f"  {kind:>18} {'I' if rank == 1 else 'II':>4}"
            mean = sum(lifts[(kind, rank, l)] for l in labels) / len(labels)
            for l in labels:
                row += f"{lifts[(kind, rank, l)] * 100:>31.1f}%"
            lo, hi = (0.03, 0.16) if kind == "concord" else ((0.03, 0.08) if rank == 1 else (0.08, 0.16))
            inside = lo - 1e-9 <= mean <= hi + 1e-9
            verdict = "ok" if inside else ("TOO SMALL" if mean < lo else "TOO BIG")
            print(row + f"{mean * 100:>7.1f}%  {verdict}")
            if not inside:
                misses.append(f"{kind} rank {rank}: lifts {mean*100:.1f}% on the mean, outside {lo*100:.0f}-{hi*100:.0f}%")
    assert not misses, "; ".join(misses)
    print("  → every rank lands in its band: a reason to think about the roster, not a wall")

# ---------------------------------------------------------------------------
# The Regalia, measured the way the resonance is: a mono team of four of a
# family of the template's kit at level I, III and V against the same three
# fights with no regalia, on the same seeds; the mean of the three. The
# readings are TEMPO-aware, because two templates buy actions (a head start,
# a knock) and a per-turn figure cancels an action bought — more of our
# actions is more turns, so damage per turn stood still while the fight
# shortened (the first cut measured the marksman's V at 1.7%). An offensive
# template is read off the damage the FOES took per action THEY got (burn
# ticks included, which is what a Lasting Word lengthens); Unbowed, a
# Bulwark and a Thief of Turns off the damage the team took per action IT
# got; a Wellspring off the share of the damage taken that its own extra
# healing gave back (a bigger heal is FEWER casts, not more healing, so the
# net figure reads nothing). Docs/PLAN.md, *Artifacts — the last item on
# the order*, option 3.
# ---------------------------------------------------------------------------

REGALIA_FAMILIES = {  # the family each template is measured on: a 5* of its kit, and its colour
    "keenEdge": ("thor", "ember"), "heavyHand": ("horus", "ember"), "firstOffTheMark": ("artemis", "ember"),
    "unbowed": ("poseidon", "ember"), "bulwark": ("athena", "ember"), "wellspring": ("isis", "ember"),
    # The oracle in its dark form: the sim reads a burn, a stun and a break
    # off a skill's name and nothing else, and the dark oracle's third skill
    # is the line-wide break — the one debuff of the five forms' lines the
    # sim can see held a turn longer. The fire form measured 0.5%.
    "lastingWord": ("odin", "umbra"), "thiefOfTurns": ("loki", "ember"),
}

def regalia_family(template):
    key, element = REGALIA_FAMILIES[template]
    if element == "ember": return FAMILIES[key]
    # A stand-in for the kit on the family's numbers, no premium: the dark
    # oracle is here for its break, not for what its dark form carries.
    _, name, stars, kit, hp, atk, dfn, spd = next(r for r in FAMILY_ROWS if r[0] == key)
    return Blueprint(f"{key}_{element}", f"{name} ({element})", element, stars, hp=hp, atk=atk, dfn=dfn, spd=spd,
                     skills=kit_skills(kit, stars, hp, atk, element=element))

REGALIA_OFFENSIVE = ("keenEdge", "heavyHand", "firstOffTheMark", "lastingWord")
REGALIA_DEFENSIVE = ("unbowed", "bulwark", "thiefOfTurns")
# What `--regalia` arms on the team so the template has something to scale:
# the warden's wall as the data has it (Shield Wall, 15% of max health, and
# the sim otherwise plays that skill as a heal) and the trickster's knock (a
# strip with a 30% bar knock at 70%, the second skill's).
REGALIA_ARMS = {"bulwark": ("shield_cast", 0.15), "thiefOfTurns": ("knock", (0.30, 0.70))}

def regalia_run(team_spec, waves, template, level, trials):
    dealt = taken = foe_taken = healed = extra = 0.0
    turns_total, wins = 0, 0
    own_turns = foe_turns = 0.0
    for s in range(trials):
        team = [mk(*t) for t in team_spec]
        arm = REGALIA_ARMS.get(template)
        if arm:
            for f in team: setattr(f, arm[0], arm[1])
        if level: apply_regalia(team, template, level)
        stats = {"dealt": {}, "taken": {}, "healed": {}, "boonHealed": {}}
        result, total = "a", 0
        for w, spec in enumerate(waves):
            result, t = simulate(team, build_stage(spec), seed=s * 7 + w, stats=stats, first_wave=(w == 0))
            total += t
            if result != "a": break
        if result == "a": wins += 1
        dealt += stats["dealt"].get("a", 0.0); taken += stats["taken"].get("a", 0.0)
        foe_taken += stats["taken"].get("b", 0.0); healed += stats["healed"].get("a", 0.0)
        extra += stats["boonHealed"].get("a", 0.0)
        own_turns += stats.get("turns", {}).get("a", 0.0); foe_turns += stats.get("turns", {}).get("b", 0.0)
        turns_total += total
    turns = max(1.0, float(turns_total))
    return {"dps": dealt / turns, "taken": taken / turns, "foe": foe_taken / turns,
            "healed": healed / turns, "extra": extra / turns, "wins": wins / trials, "turns": turns / trials,
            # The tempo readings: what the foes took per action THEY got, and
            # what the team took per action IT got.
            "foePerFoeTurn": foe_taken / max(1.0, foe_turns), "takenPerOwnTurn": taken / max(1.0, own_turns)}

def regalia_lift(template, base, run):
    if template in REGALIA_DEFENSIVE:
        return 1 - run["takenPerOwnTurn"] / base["takenPerOwnTurn"] if base["takenPerOwnTurn"] > 0 else 0.0
    if template == "wellspring":
        return run["extra"] / base["taken"] if base["taken"] > 0 else 0.0
    return run["foePerFoeTurn"] / base["foePerFoeTurn"] - 1 if base["foePerFoeTurn"] > 0 else 0.0

def regalia_fights():
    """Three fights: a chapter's boss stage in three waves, the Labyrinth's
    last level (three waves, the boss at x1.6: the one with pressure in it)
    and the arena's four-colour line."""
    arena = next(f for f in boon_fights() if f[0].startswith("Arena"))
    return [("Olympus 3 boss stage", generated_waves(CHAPTERS[3], 10)[0]),
            ("Necropolis B10", labyrinth_waves(LABYRINTHS[2], 10)),
            ("Arena, four colours", arena[3])]

def report_regalia(trials=24):
    print("\nTHE REGALIA — each template at I, III and V on a mono team of its kit, three fights, %d seeded runs each" % trials)
    print("one NAMED item per family, unlocked by awakening, levelled I-V by duplicates fed past the skill-up cap;")
    print("a striker's is crit rate, a duelist's crit damage, a marksman's the bar as each wave walks on, a bruiser's")
    print("the defence under half, a warden's the shields, a healer's the heals, an oracle's accuracy and the debuffs'")
    print("hold (from III), a trickster's the bar it moves. an offensive template is read off the damage the foes")
    print("took per action they got, Unbowed, Bulwark and a Thief of Turns off the damage the team took per action")
    print("it got, a Wellspring off the share of the damage taken its own extra healing gave back; each on the MEAN")
    print("of the three fights.")
    print("rule: no template's V tops the rank II resonance (16%%); the best V is 8-16%%, a reason to pull for the")
    print("family and never the wall a new family cannot climb; every V beats its I and is worth at least 2%%.\n")
    fights = regalia_fights()
    levels = (1, 3, 5)
    lifts = {}
    for label, waves in fights:
        for template in REGALIA_FAMILIES:
            team = [(regalia_family(template), 55, 6, 1.60)] * 4
            base = regalia_run(team, waves, template, 0, trials)
            for level in levels:
                lifts[(template, level, label)] = regalia_lift(template, base, regalia_run(team, waves, template, level, trials))
    labels = [f[0] for f in fights]
    print(f"  {'template (family)':>30} {'lvl':>4}" + "".join(f"{l[:22]:>24}" for l in labels) + f"{'mean':>8}")
    means = {}
    for template, (key, element) in REGALIA_FAMILIES.items():
        for level in levels:
            family = key if element == "ember" else f"{key}, {element}"
            row = f"  {(template + ' (' + family + ')') if level == 1 else '':>30} {'I' if level == 1 else ('III' if level == 3 else 'V'):>4}"
            mean = sum(lifts[(template, level, l)] for l in labels) / len(labels)
            means[(template, level)] = mean
            for l in labels:
                row += f"{lifts[(template, level, l)] * 100:>23.1f}%"
            print(row + f"{mean * 100:>7.1f}%")
    best = max(REGALIA, key=lambda t: means[(t, 5)])
    print(f"\n  the best V: {best} at {means[(best, 5)] * 100:.1f}%; the smallest: "
          + f"{min(REGALIA, key=lambda t: means[(t, 5)])} at {min(means[(t, 5)] for t in REGALIA) * 100:.1f}%")
    print("  the sim cannot see a Lasting Word's accuracy (its I and II read 0) nor the longer slows, silences and")
    print("  brands, only the burn and the break it holds, so the oracle's number is a floor; Unbowed reads small")
    print("  because a mono team of four bruisers with relics is seldom under half — the tank the item is for is;")
    print("  the warden's wall and the trickster's knock are armed for this report alone (REGALIA_ARMS), so no")
    print("  other report's fight moves.")
    for t in REGALIA:
        assert means[(t, 5)] <= 0.16 + 1e-9, f"{t}'s V lifts {means[(t, 5)]*100:.1f}%: over the rank II resonance's 16%, a family's own item has become a wall"
        assert means[(t, 5)] >= 0.02 - 1e-9, f"{t}'s V lifts {means[(t, 5)]*100:.1f}%: under 2% nobody feeds a fifth copy for it"
        assert means[(t, 5)] > means[(t, 1)], f"{t}: V ({means[(t, 5)]*100:.1f}%) should beat I ({means[(t, 1)]*100:.1f}%)"
    assert 0.08 - 1e-9 <= means[(best, 5)] <= 0.16 + 1e-9, f"the best V ({best}, {means[(best, 5)]*100:.1f}%) should sit in 8-16%"
    for kit, template in REGALIA_KITS.items():
        assert template in REGALIA, f"{kit}'s template {template} has no magnitudes"
    for key, template in REGALIA_HANDWRITTEN.items():
        assert template in REGALIA, f"{key}'s template {template} has no magnitudes"
    for template, table in REGALIA.items():
        assert len(table) == REGALIA_RULES["levels"] and all(a < b for a, b in zip(table, table[1:])), f"{template}'s table must rise I-V"
    print("  → every V beats its I, none tops the rank II resonance, and the best sits in 8-16%  -> correct")

def report_campaign(trials=200):
    print("\nCAMPAIGN — win rate over %d seeded battles" % trials)
    print("target: the intended team sits at 60-85%; the one below it should struggle\n")
    head = f"{'stage':>22}{'rec.pwr':>9}  "
    for name, _ in LADDERS: head += f"{name:>17}"
    print(head)
    for name, rec, waves in STAGES:
        row = f"{name:>22}{rec:>9}  "
        for _, team in LADDERS:
            wr, med = winrate_waves(team, waves, trials=trials)
            row += f"{wr*100:>11.0f}% {med:>3.0f}t"
        print(row)
    print(f"\n{'team power':>22}{'':>9}  " + "".join(
        f"{sum(mk(*t).power() for t in team):>17,}" for _, team in LADDERS))

# ScrollType.odds, grade -> chance, mirrored. Change a number in both files.
# The Light & Dark scroll is the premium scroll (2026-09-17): the only pool
# that holds a Radiance or Umbra unit, 0.8% for a 5* with no guarantee.
SCROLL_ODDS = {
    "mystical":   {3: 0.885, 4: 0.100, 5: 0.015},
    "pantheonic": {3: 0.790, 4: 0.180, 5: 0.030},
    "divine":     {4: 0.880, 5: 0.120},
    "unknown":    {3: 1.0},
    "light_dark": {3: 0.902, 4: 0.090, 5: 0.008},
    "ember":      {3: 0.820, 4: 0.150, 5: 0.030},
    "tide":       {3: 0.820, 4: 0.150, 5: 0.030},
    "gale":       {3: 0.820, 4: 0.150, 5: 0.030},
}
for _scroll, _odds in SCROLL_ODDS.items():
    assert abs(sum(_odds.values()) - 1.0) < 1e-9, f"{_scroll}: published odds must sum to 1"
LIGHT_DARK_RARE_PITY = 15          # Banner.lightAndDark.rarePity; its legendaryPity is nil

def report_gacha():
    print("\nSUMMON — 200,000 pulls on the featured banner")
    odds = SCROLL_ODDS["pantheonic"]
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

    pantheon_mean = statistics.mean(gaps)

    # LIGHT AND DARK: the premium scroll (2026-09-17). Radiance and Umbra are
    # in no pool but this one (Banner.excludingLightDark; the 0.25 / 0.12
    # weight that discounted them inside the other pools is gone with the
    # pools), the scroll's 5* rate is under one per cent, and its banner has
    # NO hard pity and so no soft pity (SummonService.single keys both off
    # Banner.legendaryPity, which is nil). The 4* guarantee at 15 stays.
    # Summoners War's L&D scroll is 0.5% with no pity; the owner asked for
    # "1% or less". Mileage (MileageService, --mileage) is the only floor.
    ld = SCROLL_ODDS["light_dark"]
    assert ld[5] <= 0.01, "the owner: a 5* Light or Dark at 1% or less"
    assert MILEAGE_PITY["light_dark"] is None, "the Light & Dark banner has no hard pity"
    rng = random.Random(11)
    since, rare_since, ld_fives, ld_gaps, ld_fours = 0, 0, 0, [], 0
    for _ in range(pulls):
        since += 1; rare_since += 1
        r = rng.random()
        stars = 5 if r < ld[5] else (4 if r < ld[5] + ld[4] else 3)
        if rare_since >= LIGHT_DARK_RARE_PITY: stars = max(4, stars)
        if stars >= 4: rare_since = 0
        if stars == 4: ld_fours += 1
        if stars == 5:
            ld_fives += 1; ld_gaps.append(since); since = 0
    ld_cost = SCROLL_DIVINITY["light_dark"]
    expected = 1 / ld[5]
    print(f"\n  LIGHT & DARK — {pulls:,} pulls on the premium scroll ({ld_cost} divinity each), the only road to Radiance and Umbra")
    print(f"  published 5* rate      {ld[5]*100:.1f}%   (4* {ld[4]*100:.0f}%, 3* {ld[3]*100:.1f}%)")
    print(f"  effective 5* rate      {ld_fives/pulls*100:.2f}%  (no hard pity, no soft pity: the published rate IS the rate)")
    print(f"  effective 4* rate      {ld_fours/pulls*100:.2f}%  (the 4* guarantee at {LIGHT_DARK_RARE_PITY} lifts it from {ld[4]*100:.0f}%)")
    print(f"  mean pulls per 5*      {statistics.mean(ld_gaps):.1f}  (expected {expected:.0f})")
    print(f"  median                 {statistics.median(ld_gaps):.0f}")
    print(f"  90th percentile        {sorted(ld_gaps)[int(len(ld_gaps)*0.9)]}")
    print(f"  worst case seen        {max(ld_gaps)}")
    for n in (100, 200, 300):
        print(f"  no 5* in {n} pulls       {(1 - ld[5]) ** n * 100:.1f}%")
    print(f"  divinity per 5* (mean) {expected * ld_cost:,.0f}  — {expected * ld_cost / (pantheon_mean * scroll_cost):.1f}x a pantheon banner's mean 5*")
    ld_mileage = mileage_price(5, "light_dark")
    print(f"  the mileage floor      {ld_mileage} scrolls ({ld_mileage * ld_cost:,} divinity), "
          f"{ld_mileage / expected:.2f}x the expected pull count — the one guarantee the scroll has")

# The campaign's tributes (Swift: `TributeService.payout`, `Chapter.relicSets`).
# Each chapter drops two sets, one stat set and one effect set of its realm's
# myth; three chests a tier pay the road (third stage), the gate (the boss)
# and the judgment (every stage at three stars). Divinity is the currency a
# Pantheon scroll costs 100 of. Change a number in both files.
CHAPTER_SETS = {
    "duat_1": ("oracle", "nemesis"), "duat_2": ("wards", "styx"),
    "olympus_1": ("aegis", "ichor"), "olympus_2": ("thunder", "fates"), "olympus_3": ("zephyr", "titanfall"),
    "yggdrasil_1": ("fury", "chains"), "yggdrasil_2": ("thunder", "wrath"), "yggdrasil_3": ("bulwark", "vigil"),
    "rome_1": ("oracle", "vigil"), "rome_2": ("ruin", "titanfall"),
    "jade_1": ("zephyr", "ichor"), "jade_2": ("wards", "wrath"),
}
# (divinity, pantheon scrolls, mystical scrolls, essences, stone, relic grade, relic quality)
TRIBUTES = {
    ("normal", "third"): (30, 1, 0, 0, None, None, None),
    ("normal", "boss"): (60, 0, 0, 3, None, 4, "rare"),
    ("normal", "flawless"): (120, 0, 2, 0, None, 5, "hero"),
    ("hard", "third"): (50, 1, 0, 2, None, None, None),
    ("hard", "boss"): (100, 0, 0, 4, None, 5, "hero"),
    ("hard", "flawless"): (180, 0, 2, 0, "whetstone_rare", 6, "hero"),
    ("hell", "third"): (80, 2, 0, 3, None, None, None),
    ("hell", "boss"): (150, 0, 0, 5, "gem_rare", 6, "hero"),
    ("hell", "flawless"): (250, 0, 3, 0, "whetstone_hero", 6, "legend"),
}


def report_tributes():
    """What the campaign pays as it is walked, and what each road drops."""
    stat_sets = {"fury", "aegis", "bulwark", "zephyr", "thunder", "ruin", "oracle", "wards"}
    print("Chapter sets (stat set + effect set):")
    seen = set()
    for chapter, sets in CHAPTER_SETS.items():
        assert len([s for s in sets if s in stat_sets]) == 1, chapter
        seen.update(sets)
        print(f"  {chapter:<12} {sets[0]:<10} {sets[1]}")
    missing = {"fury", "aegis", "bulwark", "zephyr", "thunder", "ruin", "oracle", "wards",
               "ichor", "wrath", "styx", "chains", "fates", "nemesis", "titanfall", "vigil"} - seen
    print(f"  every set on some road: {'yes' if not missing else 'MISSING ' + ', '.join(sorted(missing))}")
    print()
    print("Tributes per chapter (divinity / scrolls / essences / stone / relic):")
    for tier in ("normal", "hard", "hell"):
        total = 0
        for milestone in ("third", "boss", "flawless"):
            div, pan, mys, ess, stone, grade, quality = TRIBUTES[(tier, milestone)]
            total += div + pan * 100 + mys * 75
            relic = f"{grade}★ {quality}" if grade else "-"
            scrolls = ", ".join(x for x in [f"{pan} pantheon" if pan else "", f"{mys} mystical" if mys else ""] if x) or "-"
            print(f"  {tier:<7} {milestone:<9} {div:>4} div  {scrolls:<24} {ess} essence  {stone or '-':<15} {relic}")
        summons = total / 100
        print(f"  {tier:<7} a chapter's three chests are worth {total} divinity-equivalent, about {summons:.1f} pantheon summons")
    print()
    print("Twelve chapters × three tiers: %d chests, %d guaranteed set relics." % (
        12 * 9, 12 * sum(1 for v in TRIBUTES.values() if v[5])))


# ---------------------------------------------------------------------------
# The Night Market (NightMarketService.swift). Change a number in both files.
# ---------------------------------------------------------------------------
#
# The point of the shop is a DRACHMA SINK: before it, drachma had exactly one
# use (relic power-up), and a currency with one sink stops meaning anything
# once a player has what they want. The point of the report is the opposite
# question — that a shelf a player can re-roll must never out-earn the fight.

MARKET_WEIGHTS = {            # NightMarketService.Kind.weight
    "relic": 28, "scroll": 24, "essence": 16, "stone": 12, "energy": 12, "unit": 8,
}
MARKET_SLOTS = [(0, 6), (10, 7), (20, 8), (30, 9), (40, 10)]   # level floor -> slots
MARKET_WINDOW_MINUTES = 60
MARKET_REROLLS = [30, 45, 70, 105, 155, 230, 345, 500]          # divinity, nth of the day
MARKET_RELIC_PRICE = {6: 90_000, 5: 45_000, 4: 22_000, 3: 10_000}
MARKET_SCROLL_WEIGHTS = {     # what a scroll slot rolls
    "unknown": 26, "mystical": 24, "ember": 10, "tide": 10, "gale": 10,
    "pantheonic": 12, "light_dark": 5, "divine": 3,
}
# (currency, price for one) — the bazaar's shelf price beside it, for the
# discount a shelf you cannot choose from has to be worth.
MARKET_SCROLL_PRICE = {
    "unknown": ("drachma", 3_400), "mystical": ("drachma", 28_000),
    "ember": ("divinity", 135), "tide": ("divinity", 135), "gale": ("divinity", 135),
    "pantheonic": ("divinity", 70), "light_dark": ("divinity", 320), "divine": ("divinity", 430),
}
# What a divinity is worth in drachma, read off the two things the bazaar
# sells for both: a 4★ relic pack is 25,000 drachma and a 5★ is 150 divinity,
# and an Unknown Scroll is 5,000 drachma against a Mystical's 75 divinity.
# Both land near 300, which is the rate the market's drachma rows are judged
# against — a drachma row must never be a cheap way to buy hard currency.
DIVINITY_IN_DRACHMA = 300
BAZAAR_SCROLL_PRICE = {
    "unknown": ("drachma", 5_000), "mystical": ("divinity", 75),
    "ember": ("divinity", 200), "tide": ("divinity", 200), "gale": ("divinity", 200),
    "pantheonic": ("divinity", 100), "light_dark": ("divinity", 450), "divine": ("divinity", 600),
}
MARKET_UNIT_PRICE = {3: 40_000, 4: 250_000}     # drachma; a 5* is never on the shelf
MARKET_UNIT_FOUR_STAR_CHANCE = 0.28             # from level 12

# One of each (2026-09-23): a slot that rolls a ware already on the shelf
# draws again, up to NightMarketService.twinRedraws times. What each kind's
# stall draws, so a twin can be told from a neighbour:
MARKET_TWIN_REDRAWS = 24                        # NightMarketService.twinRedraws
MARKET_ENERGY = (20, 30, 50)                    # energyStall
MARKET_ESSENCE_IDS = 8                          # marketEssences, 2...6 of one
MARKET_ESSENCE_COUNTS = (2, 6)
MARKET_SCROLL_MULTI = ("unknown", "mystical")   # the two a slot sells 1...3 of


def market_slots(level):
    return max(n for floor, n in MARKET_SLOTS if level >= floor)


def market_relic_grades(level):
    """relicStall: never more than two grades over what the campaign pays."""
    ceiling = max(3, min(6, 3 + level // 12))
    return list(range(max(3, ceiling - 1), ceiling + 1))


def market_stone_tiers(level):
    return ["rare", "hero", "legend"] if level >= 30 else (["rare", "hero"] if level >= 15 else ["rare"])


def market_unit_pool(stars):
    """marketUnits: the fire, water and wind forms of every family of the
    grade (light and dark are the Light & Dark scroll's alone)."""
    families = (sum(1 for row in FAMILY_ROWS if row[2] == stars)
                + sum(1 for _key, bp in HANDWRITTEN if bp.stars == stars))
    return 3 * families


def market_ware(level, rng):
    """One slot's roll (NightMarketService.ware) as a hashable grant: equal
    tuples are the same ware, as equal `Grant`s are in the Swift."""
    kinds = list(MARKET_WEIGHTS)
    kind = rng.choices(kinds, weights=[MARKET_WEIGHTS[k] for k in kinds])[0]
    if kind == "relic":
        return ("relic", rng.choice(market_relic_grades(level)))
    if kind == "scroll":
        scrolls = list(MARKET_SCROLL_WEIGHTS)
        scroll = rng.choices(scrolls, weights=[MARKET_SCROLL_WEIGHTS[s] for s in scrolls])[0]
        return ("scroll", scroll, rng.randint(1, 3) if scroll in MARKET_SCROLL_MULTI else 1)
    if kind == "essence":
        return ("essence", rng.randrange(MARKET_ESSENCE_IDS), rng.randint(*MARKET_ESSENCE_COUNTS))
    if kind == "stone":
        return ("stone", rng.choice(market_stone_tiers(level)), rng.choice(("whetstone", "gem")))
    if kind == "energy":
        return ("energy", rng.choice(MARKET_ENERGY))
    stars = 4 if level >= 12 and rng.random() < MARKET_UNIT_FOUR_STAR_CHANCE else 3
    return ("unit", stars, rng.randrange(market_unit_pool(stars)))


def market_shelf(level, rng, redraws=MARKET_TWIN_REDRAWS):
    """A whole shelf, slot by slot, each twin drawn again (NightMarketService.stalls)."""
    shelf = []
    for _ in range(market_slots(level)):
        ware = market_ware(level, rng)
        tries = 0
        while tries < redraws and ware in shelf:
            ware = market_ware(level, rng)
            tries += 1
        shelf.append(ware)
    return shelf


# ---------------------------------------------------------------------------
# Athena's Counsel (CounselService.swift). Change a number in both files.
# ---------------------------------------------------------------------------
#
# The road's job is to carry a new player through the first month, so the
# question this answers is whether it pays enough to matter without paying so
# much that the campaign stops being the way to earn. Divinity-equivalent, at
# the rates the bazaar sells at: a pantheon scroll 100, a mystical 75, a divine
# 600, a light & dark 450, an unknown 5,000 drachma.
#
# (tier, [step divinity-equivalents], tier prize divinity-equivalent)
COUNSEL = {
    "initiate": (
        # mystical, 10k drachma, 3 unknown, 15k drachma, 30 energy, 25k drachma,
        # 30 div, 2 mystical, 50 div, pantheon + 100 div
        [75, 33, 51, 50, 30, 83, 30, 150, 50, 200], 600),
    "adept": (
        # 80 div, 40k drachma, 5 mid essence, 2 mystical, 100 div, 50k drachma,
        # pantheon, 120 div, 5 unknown, 100 div + 2 high essence
        [80, 133, 75, 150, 100, 167, 100, 120, 85, 160], 850),
    "hierophant": (
        # 200 div, pantheon, 200 div, hero whetstone, 150 div, 250 div, 150 div,
        # pantheon, 300 div, pantheon + 200 div
        [200, 100, 200, 90, 150, 250, 150, 100, 300, 300], 1_350),
}
COUNSEL_TIER_STEPS = 10


def report_counsel():
    """What Athena's road pays, against what the campaign pays for the same
    month. A checklist that out-earns the game it is teaching is a checklist
    the player does instead of playing."""
    print("\nATHENA'S COUNSEL — the first month, in divinity-equivalent")
    total = 0
    for tier, (steps, prize) in COUNSEL.items():
        assert len(steps) == COUNSEL_TIER_STEPS, tier
        walk = sum(steps)
        total += walk + prize
        print(f"  {tier:<11} {len(steps)} steps {walk:>6,}  + tier prize {prize:>6,}"
              f"  = {walk + prize:>6,}")
    print(f"  {'the whole road':<11} {' ' * 9}{total:>6,} divinity-equivalent, "
          f"about {total / 100:.0f} pantheon summons")

    # Against what a first month actually pays. The first cut of this compared
    # the road against TWELVE CHAPTERS OF FIRST CLEARS ALONE and reported 125%
    # — a real finding about the hierophant tier (three Divine Scrolls on a
    # checklist is a second gacha) but against a denominator that left out most
    # of a month's income. Both were wrong and both are fixed: the tier was cut,
    # and the baseline below names everything it counts so it can be argued
    # with rather than trusted.
    first_clears = 12 * (220 + 7_350 / 300)      # report_economy, per chapter
    normal_chests = 12 * 460                      # report_tributes, Normal
    hard_chests = 6 * 580                         # half the chapters, on Hard
    login = 30 / 7 * 473                          # the seven-day gift, a month of it
    campaign_month = first_clears + normal_chests + hard_chests + login
    print(f"\n  a first month: {first_clears:,.0f} first clears + {normal_chests:,.0f} "
          f"Normal chests + {hard_chests:,.0f} Hard chests + {login:,.0f} login gifts")
    print(f"  {'':<14}= {campaign_month:,.0f} divinity-equivalent "
          f"(the daily missions are NOT in this, so it is a floor)")
    share = total / campaign_month
    print(f"  the road is {share * 100:.0f}% of that")
    verdict = ("a spine, not a substitute — correct" if share < 0.6
               else "THE ROAD OUT-EARNS THE GAME — cut the step rewards")
    print(f"  → {verdict}")
    print("  (every step is measured off the save, so nothing here can be farmed twice)")


def report_shop():
    """The Night Market: what a shelf holds, what it costs, and the one thing
    that must not be true — that re-rolling beats playing."""
    total = sum(MARKET_WEIGHTS.values())
    print("\nTHE NIGHT MARKET — a rolled shelf, an hour at a time")
    print(f"  slots: " + ", ".join(f"{n} from level {lvl}" for lvl, n in MARKET_SLOTS))
    print(f"  the shelf turns over every {MARKET_WINDOW_MINUTES} minutes for nothing")
    print("  paid re-rolls within a day (divinity): " + ", ".join(str(p) for p in MARKET_REROLLS)
          + " and 500 thereafter")
    print()
    print(f"  {'ware':>9}{'weight':>8}{'share':>8}   per 8-slot shelf")
    for kind, weight in MARKET_WEIGHTS.items():
        share = weight / total
        print(f"  {kind:>9}{weight:>8}{share*100:>7.0f}%   {share*8:>5.1f}")

    # One of each. Before the rule a shelf could hold the same ware twice —
    # run 221's showed +20 energy for 18,000 twice, run 220's three 3★
    # relics, and at level 1 a relic slot has one grade to roll. Measured on
    # rolled shelves, with and without the redraw: how often a shelf had a
    # twin, and how many relics a shelf holds (the relic is the ware the rule
    # thins, since it has the fewest faces at a level).
    rng = random.Random(2551)
    trials = 10_000
    print(f"\n  one of each: a slot that rolls a ware already on the shelf draws again"
          f" (up to {MARKET_TWIN_REDRAWS} times)")
    print(f"  {'level':>7}{'slots':>7}{'a twin, before':>16}{'after':>7}   relics a shelf, before -> after")
    for level in (1, 12, 24, 40):
        before = [market_shelf(level, rng, redraws=0) for _ in range(trials)]
        after = [market_shelf(level, rng) for _ in range(trials)]
        twins_before = sum(len(set(s)) < len(s) for s in before) / trials
        twins_after = sum(len(set(s)) < len(s) for s in after) / trials
        relics_before = sum(sum(w[0] == "relic" for w in s) for s in before) / trials
        relics_after = sum(sum(w[0] == "relic" for w in s) for s in after) / trials
        print(f"  {level:>7}{market_slots(level):>7}{twins_before * 100:>15.0f}%{twins_after * 100:>6.0f}%"
              f"   {relics_before:.2f} -> {relics_after:.2f}")
        assert twins_after == 0, f"level {level}: a rolled shelf still shows a ware twice"
    # The redraw always ends: the chance a draw repeats the shelf is at most
    # the five or nine likeliest wares' share, and twenty-four of those in a
    # row must be vanishingly rare.
    for level in (1, 12, 24, 40):
        faces = {}
        for _ in range(trials * 4):
            ware = market_ware(level, rng)
            faces[ware] = faces.get(ware, 0) + 1
        worst = sum(sorted(faces.values(), reverse=True)[:market_slots(level) - 1]) / (trials * 4)
        assert worst ** MARKET_TWIN_REDRAWS < 1e-6, f"level {level}: the redraw can run out ({worst:.2f} a draw)"
    print("  -> no rolled shelf shows a ware twice  -> correct")

    print("\n  scroll slot, and the bazaar's price beside it")
    scroll_total = sum(MARKET_SCROLL_WEIGHTS.values())
    for scroll, weight in MARKET_SCROLL_WEIGHTS.items():
        cur, price = MARKET_SCROLL_PRICE[scroll]
        bcur, bprice = BAZAAR_SCROLL_PRICE[scroll]
        # Compare like with like: a drachma row against a divinity shelf price
        # is judged at the rate above, since the whole point of the row is to
        # give drachma somewhere to go.
        mine = price if cur == "drachma" else price * DIVINITY_IN_DRACHMA
        theirs = bprice if bcur == "drachma" else bprice * DIVINITY_IN_DRACHMA
        delta = (1 - mine / theirs) * 100
        cut = f"{delta:>3.0f}% off" if delta >= 0 else f"{-delta:>3.0f}% dearer"
        # A drachma row that is DEARER at the rate is right, not a mistake: it
        # is the only way to buy a hard-currency scroll with soft coin, and a
        # premium is what stops it being a mint.
        note = "" if cur == bcur else "  (soft coin for a hard-coin scroll — the premium is the point)"
        print(f"  {scroll:>11}{weight * 100 // scroll_total:>4}%   {price:>7,} {cur:<8}"
              f"  bazaar {bprice:>6,} {bcur:<8}  {cut}{note}")

    # The one thing that must not be true. A Divine Scroll is the best row on
    # the shelf; how much divinity does re-rolling until one appears cost,
    # against buying it outright in the bazaar?
    slots = 8
    per_shelf_weights = 1 - (1 - (MARKET_WEIGHTS["scroll"] / total)
                             * (MARKET_SCROLL_WEIGHTS["divine"] / scroll_total)) ** slots
    # With one of each, a twin's redraw is one more chance at the Divine
    # Scroll, so the shelf's own rate is measured on rolled shelves (level 20,
    # eight slots) and never read off the weights alone.
    rolled = [market_shelf(20, rng) for _ in range(trials * 4)]
    per_shelf = sum(("scroll", "divine", 1) in s for s in rolled) / len(rolled)
    shelves = 1 / per_shelf
    # The re-roll price climbs, so the bill for N re-rolls in one day is the
    # head of the table plus 500 for the rest.
    def reroll_bill(n):
        return sum(MARKET_REROLLS[min(i, len(MARKET_REROLLS) - 1)] for i in range(int(n)))
    bill = reroll_bill(shelves)
    outright = BAZAAR_SCROLL_PRICE["divine"][1] + MARKET_SCROLL_PRICE["divine"][1]
    print(f"\n  a Divine Scroll is on {per_shelf*100:.1f}% of rolled shelves ({per_shelf_weights*100:.1f}% by the"
          f" weights alone), so {shelves:.0f} re-rolls to find one:")
    print(f"    {bill:,} divinity of re-rolls, then {MARKET_SCROLL_PRICE['divine'][1]} to buy it"
          f"  = {bill + MARKET_SCROLL_PRICE['divine'][1]:,}")
    print(f"    the bazaar sells it outright for {BAZAAR_SCROLL_PRICE['divine'][1]}")
    verdict = "chasing is dearer than buying — correct" if bill + MARKET_SCROLL_PRICE["divine"][1] > BAZAAR_SCROLL_PRICE["divine"][1] \
        else "CHASING IS CHEAPER THAN BUYING — raise the re-roll price"
    print(f"    → {verdict}")
    print(f"    (waiting out the free hourly refresh finds one in about {shelves:.0f} hours, which is the intended way)")
    assert bill + MARKET_SCROLL_PRICE["divine"][1] > BAZAAR_SCROLL_PRICE["divine"][1], \
        "re-rolling the market for a Divine Scroll must cost more than the bazaar's own"
    _ = outright

    print("\n  the unit row, the one that makes a player look")
    print(f"    3★ {MARKET_UNIT_PRICE[3]:,} drachma, 4★ {MARKET_UNIT_PRICE[4]:,} drachma, "
          f"5★ never — the genre's own line, and what keeps the summon screen worth opening")
    unit_share = MARKET_WEIGHTS["unit"] / total
    four = unit_share * MARKET_UNIT_FOUR_STAR_CHANCE
    print(f"    a unit is on {(1 - (1 - unit_share) ** slots) * 100:.0f}% of shelves; "
          f"a 4★ on {(1 - (1 - four) ** slots) * 100:.0f}%")
    chapter_one = 700 + 950 + 1200 + 1500 + 3000
    print(f"    a 3★ costs {MARKET_UNIT_PRICE[3] / chapter_one:.1f} full clears of chapter 1, "
          f"a 4★ {MARKET_UNIT_PRICE[4] / chapter_one:.0f}")

    print("\n  relics on the shelf, against the bazaar's packs")
    for grade in (6, 5, 4, 3):
        print(f"    {grade}★ {MARKET_RELIC_PRICE[grade]:>7,} drachma")
    print("    the bazaar: 4★ 25,000 drachma, 5★ 150 divinity — the market is the cheaper")
    print("    4★ and the only place a 6★ is bought with coin at all.")


def report_relics():
    """The relic hunt: what a drop's quality costs in runs, what a stone is
    worth against a roll, and the bill to a milestone with the power-up odds."""
    print("\nRELICS — quality odds by grade (percent), and runs per Legend")
    print(f"  {'grade':>6}  " + "".join(f"{n:>8}" for n in QUALITY_NAMES) + "   runs/Legend  mean subs")
    for grade in range(1, 7):
        w = QUALITY_WEIGHTS[grade]
        legend = w[4] / 100
        mean_subs = sum(i * p for i, p in enumerate(w)) / 100
        runs = f"{1 / legend:.0f}" if legend else "never"
        print(f"  {grade:>5}*  " + "".join(f"{p:>8}" for p in w) + f"   {runs:>11}  {mean_subs:>9.2f}")
    print("  Hell tiers floor a drop at Magic, the raids at Rare (StageRewards.qualityFloor).")
    print("\n  a 6* sub roll: base × 0.75–1.25; a whetstone adds, a gem replaces, as a fraction of the base")
    print(f"  {'stone':>18}  {'SPD':>10}  {'ATK%':>12}  {'CRIT':>12}  {'HP':>10}  cost")
    for (kind, tier), (lo, hi) in STONE_RANGES.items():
        cells = []
        for stat, pct in (("spd", False), ("atk%", True), ("crit", True), ("hp", False)):
            b = sub_stat_base(stat)
            if pct:
                cells.append(f"{lo*b*100:.1f}–{hi*b*100:.1f}%")
            else:
                cells.append(f"{lo*b:.1f}–{hi*b:.1f}")
        print(f"  {tier + ' ' + kind:>18}  {cells[0]:>10}  {cells[1]:>12}  {cells[2]:>12}  {cells[3]:>10}  {STONE_COSTS[(kind, tier)]:,}")
    roll = sub_stat_base("spd")
    print(f"  (a 6* SPD roll is {roll*0.75:.1f}–{roll*1.25:.1f}; the genre's Legend grind is +4–5 and its Legend gem 8–10)")
    print("\n  power-up to a milestone, 6*: attempts and drachma expected with the odds")
    for target in (3, 6, 9, 12, 15):
        attempts = sum(1 / POWER_UP_CHANCES[l] for l in range(target))
        cost = sum((100 * 36 + l * 100 * 36 // 3) / POWER_UP_CHANCES[l] for l in range(target))
        print(f"    to +{target:<2}  {attempts:5.1f} attempts  {cost:>9,.0f} drachma")


def report_economy():
    print("\nECONOMY — first-clear income vs. upgrade costs")
    drachma = [700, 950, 1200, 1500, 3000]
    print(f"  chapter 1 full clear     {sum(drachma):,} drachma + 220 divinity")
    # RelicService.powerUpChances: sure to +3, then a step down a level; a
    # failed attempt keeps the drachma, so the expected bill is cost / chance.
    chances = [1.0, 1.0, 1.0, 0.95, 0.90, 0.85, 0.80, 0.75, 0.70, 0.65, 0.60, 0.55, 0.50, 0.45, 0.40]
    flat = sum(100*36 + l*100*36//3 for l in range(15))
    expected = sum((100*36 + l*100*36//3) / chances[l] for l in range(15))
    print(f"  one relic to +15, no fails {flat:,} drachma (6*)")
    print(f"  one relic to +15, expected {expected:,.0f} drachma (6*) with the power-up odds")
    print(f"  6* evolution ladder      {3000+8000+20000+60000+150000:,} drachma")
    print("  → chapter 1 alone funds roughly one relic. Grinding is the game.")

# WHAT DROPS WHERE — every source ranked by the power it asks, against the
# relic grade it pays. Every formula below is the REAL one, read off
# StageDatabase and DungeonDatabase, not an estimate.
#
# The owner, 2026-09-16: "make sure theres a progression of runes based on the
# difficulty of levels and all. Cant be giving 6 star relics to easy matches."
# He was right. The first run of this report found chapter 1 on HELL asking
# about 15,000 power and paying a 6* — the same grade as Labyrinth B10, which
# asks 30,645 — because `relicGradeFloor` was FLAT across all twelve chapters.
# Once that was true every harder thing in the game was something a softer
# thing had already out-paid.
LAB_POWER = lambda level: 2_200 * (1.34 ** (level - 1))          # DungeonDatabase.labyrinth
LAB_GRADE = lambda level: min(6, 3 + (level - 1) // 3)           # labyrinthGrade
HALL_POWER = lambda floor: 3_000 * (1.65 ** (floor - 1))         # DungeonDatabase.hall
HALL_GRADE = lambda floor: min(5, 2 + floor)                     # capped at 5*: the hall is the ESSENCE farm
TOWER_POWER = lambda floor: 2_800 + floor * 550                  # DungeonDatabase.towerFloor
TOWER_GRADE = lambda floor: min(6, 3 + (floor - 1) // 16)        # towerGrade

# CampaignDifficulty.relicGradeFloor(chapterOrder:) — climbs with the ROAD as
# well as the tier, which is the fix.
def tier_floor(tier, chapter):
    step = max(0, chapter - 1) // 3
    return {"normal": 0, "hard": min(6, 3 + step), "hell": min(6, 4 + step)}[tier]

TIER_POWER_SCALE = {"normal": 1.0, "hard": 1.9, "hell": 3.2}     # CampaignDifficulty.powerScale

# Each chapter's boss stage: its Normal power and the grade the stage itself
# pays before any floor. Duat 1 is hand-written (7,000, a guaranteed 4*);
# every generated chapter is 2500 x powerScale x 1.18^9 at stage 10, and its
# boss pays 4*.
CHAPTER_POWER_SCALE = [None, 2.2, 3.2, 4.4, 6.0, 8.0, 10.5, 13.5, 17.0, 21.0, 26.0]
def chapter_boss_power(chapter):
    if chapter == 1: return 7_000
    return 2_500 * CHAPTER_POWER_SCALE[chapter - 1] * (1.18 ** 9)
CAMPAIGN_BOSS_GRADE = 4

def report_drops():
    rows = []
    for level in range(1, 11):
        rows.append((LAB_POWER(level), LAB_GRADE(level), f"Labyrinth B{level}"))
    for floor in range(1, 6):
        rows.append((HALL_POWER(floor), HALL_GRADE(floor), f"Hall of Essence B{floor}"))
    for floor in (1, 20, 40, 50, 60, 80, 100):
        rows.append((TOWER_POWER(floor), TOWER_GRADE(floor), f"Endless Tower F{floor}"))
    for chapter in (1, 4, 8, 11):
        base = chapter_boss_power(chapter)
        for tier, scale in TIER_POWER_SCALE.items():
            # The stage keeps its own grade when that is higher than the floor.
            grade = max(CAMPAIGN_BOSS_GRADE, tier_floor(tier, chapter))
            rows.append((base * scale, grade, f"chapter {chapter} boss {tier}"))
    rows.sort()

    print("\nWHAT DROPS WHERE — every source by the power it asks, against the grade it pays")
    print("a source paying MORE than something harder is a leak\n")
    print(f"{'source':>28}{'asks':>10}{'pays':>7}")
    best_so_far = 0
    leaks = []
    for power, grade, label in rows:
        flag = ""
        if grade < best_so_far:
            flag = "   <- softer already paid " + str(best_so_far)
            leaks.append((label, grade, best_so_far))
        elif grade > best_so_far:
            best_so_far = grade
        print(f"{label:>28}{power:>10,.0f}{grade:>6}*{flag}")

    print(f"\n  where each grade first becomes available:")
    for target in (4, 5, 6):
        first = min((r for r in rows if r[1] >= target), key=lambda r: r[0], default=None)
        if first:
            print(f"    {target}*  {first[2]}, at {first[0]:,.0f} power")

    print(f"\n  chapter 1 on Hell asks {chapter_boss_power(1) * TIER_POWER_SCALE['hell']:,.0f} and pays "
          f"{max(CAMPAIGN_BOSS_GRADE, tier_floor('hell', 1))}* (it paid 6* before this).")
    print(f"  Tower F50 asks {TOWER_POWER(50):,.0f} and pays {TOWER_GRADE(50)}*, against Labyrinth B10's "
          f"{LAB_GRADE(10)}* at {LAB_POWER(10):,.0f} —")
    print("  the two endgame ladders now reach 6* at the same difficulty, which is the")
    print("  point: the Tower's own notes say floor 50 needs a maxed 6* team, and it used")
    print(f"  to pay a 5* for it.")
    print(f"  Hall B5 asks {HALL_POWER(5):,.0f} and pays {HALL_GRADE(5)}* — the essence farm no longer")
    print(f"  out-drops the relic dungeon (Labyrinth B9 pays {LAB_GRADE(9)}* at {LAB_POWER(9):,.0f}).")

    if leaks:
        print(f"\n  {len(leaks)} inversions remain, each a softer source out-paying a harder one:")
        for label, grade, better in leaks:
            print(f"    {label} pays {grade}* where something softer paid {better}*")
        print("  (a lower tier of a LATER chapter legitimately sits high on this axis and")
        print("   pays less than an earlier chapter's Hell; those are the expected ones)")
    else:
        print("\n  -> no inversions: nothing soft out-pays something hard")

# Choice of two on a sub-stat roll, mirrored from RelicService.candidates.
#
# A roll is subStatBase(kind, grade) * U(0.75, 1.25). Offering TWO candidates
# and letting the player take one is a best-of-two, which raises the mean —
# so the question this report exists to answer is BY HOW MUCH, before the
# feature is called free.
#
# Only the GROW rolls (a relic that already has four subs) can be measured in
# one currency: both candidates are a bump to an existing sub, so "better" is
# simply the bigger number. The ADD rolls offer two different KINDS — SPD +3
# against CRIT DMG +5% — whose lift is RELEVANCE and not magnitude, and a
# single number for that would be invented rather than measured. Said out
# loud below rather than papered over.
SUB_ROLL_SPREAD = (0.75, 1.25)   # RelicService.subStatRoll

def report_targeting(trials=200_000):
    import random as _r
    lo, hi = SUB_ROLL_SPREAD
    rng = _r.Random(20260916)

    one = sum(rng.uniform(lo, hi) for _ in range(trials)) / trials
    rng = _r.Random(20260916)
    best = sum(max(rng.uniform(lo, hi), rng.uniform(lo, hi)) for _ in range(trials)) / trials

    print("\nRELIC TARGETING — what choice-of-two costs in balance")
    print("a roll is subStatBase(kind, grade) x U(%.2f, %.2f); the player takes one of two\n"
          % (lo, hi))
    print(f"{'':>26}{'one roll':>11}{'best of two':>14}{'lift':>9}")
    print(f"{'mean multiplier':>26}{one:>11.4f}{best:>14.4f}{(best / one - 1) * 100:>8.1f}%")

    # A relic that drops with four subs grows one at each of +3/+6/+9/+12:
    # four grow rolls, and every one of them is a best-of-two.
    grows = 4
    print(f"\n  a Legend relic (four subs at the drop) takes {grows} GROW rolls on the way to +12,")
    print(f"  so its rolled sub-stat total ends about {(best / one - 1) * 100:.1f}% higher than before —")
    print(f"  {grows} rolls x the lift, spread across four subs.")

    # The honest limit of the measurement.
    print("\n  the ADD rolls are NOT in that number. A relic with fewer than four subs is")
    print("  offered two different KINDS, and picking CRIT DMG over DEF% is worth a great")
    print("  deal to a player and nothing at all to a spreadsheet. The lift there is")
    print("  relevance, which is the point of the feature and cannot be priced here.")

    verdict = "acceptable" if (best / one - 1) < 0.20 else "TOO MUCH — narrow the second candidate"
    print(f"\n  -> {(best / one - 1) * 100:.1f}% on the measurable half: {verdict}")
    print("  (if it were too much the fix is to offer the SAME stat at a second value")
    print("   rather than a free second draw, not to drop the choice)")

# Mileage, mirrored from MileageService.swift.
#
# A point per summon on a banner, spent on a unit of the player's choosing
# from that banner's pool. The price is anchored to the BANNER'S OWN hard
# pity — 1.7x what the guarantee costs — with a flat divinity target as a
# second floor for the banners that have no hard pity.
#
# The first cut used the divinity target alone and this report is what caught
# it: a flat 15,000-divinity 5* came out at 0.62 of the Divine Scroll's pity
# and 0.28 of Light & Dark's, because those banners guarantee in 40 and 120
# pulls where the pantheon banner takes 90. Mileage under the pity is not a
# floor, it is the fast road.
#
# And a THIRD floor since 2026-09-17, when the Light & Dark banner lost its
# hard pity (the premium): on a banner with NO guarantee the anchor is the
# EXPECTED pull count of the best grade — one over its rate — at 1.3x,
# rounded up (MileageService.expectedMultiple, anchorPoints). Without it the
# flat target priced a 5* Light or Dark at 33 scrolls against the 125 an
# expected one costs; with it 163. The mystical and unknown scrolls have no
# hard pity either and are untouched: their targets are the higher floor.
MILEAGE_TARGET = {3: 2_000, 4: 6_000, 5: 15_000}      # divinityTarget
MILEAGE_PITY_MULTIPLE = 1.7                            # pityMultiple
MILEAGE_EXPECTED_MULTIPLE = 1.3                        # expectedMultiple
MILEAGE_GRADE_SHARE = {5: 1.0, 4: 0.40, 3: 0.135}      # gradeShare
SCROLL_DIVINITY = {                                    # ScrollType.divinityPrice
    "pantheonic": 100, "mystical": 75, "divine": 600,
    "light_dark": 450, "ember": 200, "tide": 200, "gale": 200,
    "unknown": 25,                                     # not sold for divinity; pullValue's fallback
}
# Banner.legendaryPity; the Light & Dark banner has none since 2026-09-17.
MILEAGE_PITY = {
    "pantheonic": 90, "mystical": None, "divine": 40,
    "light_dark": None, "ember": 120, "tide": 120, "gale": 120, "unknown": None,
}
# The odds of the best grade each scroll can give, off SCROLL_ODDS.
MILEAGE_BEST_ODDS = {scroll: odds[max(odds)] for scroll, odds in SCROLL_ODDS.items()}

def mileage_anchor(scroll):
    """MileageService.anchorPoints: 1.7 hard pities, or, with no hard pity,
    1.3 expected pulls of the best grade, rounded up."""
    pity = MILEAGE_PITY[scroll]
    if pity: return pity * MILEAGE_PITY_MULTIPLE
    return math.ceil(MILEAGE_EXPECTED_MULTIPLE / max(0.0001, MILEAGE_BEST_ODDS[scroll]))

def mileage_price(stars, scroll):
    anchored = mileage_anchor(scroll) * MILEAGE_GRADE_SHARE[stars]
    target = MILEAGE_TARGET[stars] / SCROLL_DIVINITY[scroll]
    return max(10, round(max(anchored, target)))

def report_mileage():
    print("\nMILEAGE — the floor under bad luck: a point a pull, a unit you NAME")
    print("price = max(1.7 x the banner's own hard pity — or, with no hard pity, 1.3 x the expected pulls — and a flat divinity target)\n")
    print(f"{'banner scroll':>14}{'a pull':>9}{'5* pts':>9}{'4* pts':>9}{'3* pts':>9}"
          f"{'5* costs':>12}{'hard pity':>11}{'expected':>10}{'ratio':>10}")
    worst = None
    ld_ratio = None
    for scroll in ("pantheonic", "mystical", "divine", "light_dark", "ember", "unknown"):
        pull = SCROLL_DIVINITY[scroll]
        five, four, three = (mileage_price(s, scroll) for s in (5, 4, 3))
        spend = five * pull
        pity = MILEAGE_PITY[scroll]
        pity_spend = pity * pull if pity else None
        expected = 1 / MILEAGE_BEST_ODDS[scroll]
        if pity_spend:
            ratio_value = spend / pity_spend
            ratio = f"{ratio_value:.2f}x pity"
            worst = ratio_value if worst is None else min(worst, ratio_value)
        else:
            ratio_value = five / expected
            ratio = f"{ratio_value:.2f}x avg"
            if scroll == "light_dark": ld_ratio = ratio_value
        print(f"{scroll:>14}{pull:>7}dv{five:>9}{four:>9}{three:>9}"
              f"{spend:>11,}{(f'{pity_spend:,}' if pity_spend else '-'):>11}{expected:>10.0f}{ratio:>10}")

    print("\n  read the last column as: naming the 5* you want costs this much more than")
    print("  letting the hard pity hand you a RANDOM one — or, on a banner with no pity,")
    print("  than the average road to one.")
    if worst is not None:
        verdict = "correct" if worst >= 1.5 else "WRONG — mileage undercuts the pity counter"
        print(f"  the cheapest ratio on any banner with a pity is {worst:.2f}x -> {verdict}")
    if ld_ratio is not None:
        verdict = "correct" if ld_ratio >= MILEAGE_EXPECTED_MULTIPLE - 1e-9 else "WRONG — the premium's only floor is under its average"
        print(f"  the Light & Dark 5* costs {ld_ratio:.2f}x its expected pull count "
              f"(floor {MILEAGE_EXPECTED_MULTIPLE}x) -> {verdict}")
        assert ld_ratio >= MILEAGE_EXPECTED_MULTIPLE - 1e-9, verdict

    # The thing that must not be true: farming a cheap banner to cash out a
    # dear unit. It cannot be, because points are per banner and a banner's
    # points only buy that banner's own pool.
    print("\n  the exploit that is closed by construction: points are PER BANNER and buy")
    print("  only that banner's pool, so the Unknown Scroll's 3*-only pool cannot be")
    print("  farmed into a 5* god. One global pool would have been exactly that.")

    # The selector.
    print("\nSELECTOR — one 4* of the Duat, picked on day one")
    print(f"  worth {MILEAGE_TARGET[4]:,} divinity-equivalent, about "
          f"{MILEAGE_TARGET[4] // SCROLL_DIVINITY['pantheonic']} pantheon summons")
    print("  Epic Seven gives a Selective Summon at account creation and it is credited")
    print("  as one of its biggest free-to-play improvements. The point is not the unit:")
    print("  it is that the first thing a player does in a gacha is a CHOICE.")
    print("  Once, ever (Player.selectorClaimed), and never a 5*.")

# The sweep, mirrored from SweepService.swift and GameStore.sweep.
#
# A sweep changes NO number in the economy: it costs the same energy and pays
# the same drops as sitting through the fights. What it changes is TIME, and
# the one place it can pay more than a manual run is the three-star bonus,
# which it always earns because the gate is three stars. Both are measured
# below, because "it changes nothing" is a claim and not a fact until it is.
SWEEP_MAX_RUNS = 20
ENERGY_MAX = 80                 # Player.wallet.maxEnergy at level 1
ENERGY_MINUTES = 5              # GameStore.refreshEnergy: one energy per 5 minutes
STAR_BONUS = 1.25               # CampaignService.applyRewards

# (what it is, energy a run, minutes a run actually takes on the phone)
#
# The minutes are measured off the battle contracts, not guessed: a turn is
# about 3.5 s of animation at 1x (a 1.3 s basic, a dash out and back, the
# damage number), a campaign wave settles in 6-9 turns and a stage is three
# waves, so a three-wave stage is roughly 2 minutes at 1x and 70 s at the 2x
# the auto-repeat runs at. A Labyrinth level is longer: its third wave is a
# boss with two adds.
SWEEP_STAGES = [
    ("Duat 1-1, three waves",        3,  1.1),
    ("a mid chapter stage",          4,  1.3),
    ("a chapter boss",               6,  1.8),
    ("a Hall of Essence floor",      8,  1.5),
    ("Labyrinth B7, three waves",   12,  2.4),
    ("Labyrinth B10, three waves",  12,  2.9),
]

def report_sweep():
    print("\nSWEEP — the same energy, the same drops, none of the minutes")
    print("gate: three stars on this stage at this tier, AND the campaign team still")
    print("      meets its recommended power (SweepService.canSweep)\n")
    print(f"{'stage':>28}{'energy':>8}{'a full bar':>12}{'fought':>10}{'swept':>8}{'saved':>9}")
    for name, cost, minutes in SWEEP_STAGES:
        runs = ENERGY_MAX // cost
        fought = runs * minutes
        # A sweep is one tap and one sheet: call it ten seconds whatever N is.
        swept = 10 / 60
        print(f"{name:>28}{cost:>8}{runs:>9} runs{fought:>9.0f}m{swept:>7.1f}m{fought - swept:>8.0f}m")

    hours = ENERGY_MAX * ENERGY_MINUTES / 60
    print(f"\n  a full bar of {ENERGY_MAX} energy refills in {hours:.1f} hours at one per {ENERGY_MINUTES} minutes,")
    print(f"  so the cap on farming is the ENERGY, not the patience — which is what makes")
    print(f"  a sweep safe to give away: it spends the same bar in the same day.")

    # The one place a sweep pays more than a fight.
    print("\n  the only reward difference: a sweep is always a THREE-star clear, so it")
    print(f"  always takes the {STAR_BONUS:.2f}x drachma and unit-EXP bonus. A manual run that")
    print("  loses a unit takes 1.00x. Against a player who was already three-starring")
    print("  the stage — which the gate requires him to have done once — that is 0%;")
    print("  against a sloppy auto-repeat it is up to 25% more drachma.")
    print("  → intended: the three-star rating was a decoration on the map until now.")

    # And what it deliberately does NOT do.
    print("\n  what a sweep does NOT give: a first clear (impossible, three stars implies")
    print("  cleared), a star rating it has not already earned (the high-water mark only")
    print("  ever rises), or a way past the energy. It DOES pay the quests, the unit EXP,")
    print("  the tower milestones and the tribute stars, because it goes through the same")
    print("  CampaignService.settle a fought run does.")

def report_tune(trials=140):
    """Search each stage's enemy level for the win rate it is supposed to have.

    Hand-iterating five stages against six ladders is slow and I get it wrong;
    stating the intended difficulty and solving for it is both faster and
    honest about what the curve is meant to be."""
    targets = [
        # stage index, which ladder it is tuned against, target win rate
        (0, 0, 0.97),   # tutorial: the day-one account clears it, all three waves
        (1, 1, 0.90),   # the "get a second unit" wall: three waves are past a solo
        (2, 1, 0.80),   # two units, levelled
        (3, 2, 0.80),   # three units
        (4, 3, 0.80),   # the chapter boss: four units, no evolution required
    ]
    print("\nSTAGE TUNING — solving enemy level for the intended win rate")
    print(f"{'stage':>22}{'tuned against':>22}{'target':>8}{'level':>7}{'actual':>8}")
    for si, li, target in targets:
        name, rec, waves = STAGES[si]
        team = LADDERS[li][1]
        best = None
        base = waves[-1][-1][1]
        for lvl in range(1, 46):
            probe = []
            for wave in waves:
                probe.append([(e[0], max(1, lvl + e[1] - base), e[2]) + tuple(e[3:]) for e in wave])
            wr, _ = winrate_waves(team, probe, trials=trials)
            if best is None or abs(wr - target) < abs(best[1] - target):
                best = (lvl, wr)
            if wr < target - 0.30 and lvl > 3:
                break
        flag = "" if abs(best[1] - target) < 0.12 else "   <- level alone cannot reach this; change the composition"
        print(f"{name:>22}{LADDERS[li][0]:>22}{target*100:>7.0f}%{best[0]:>7}{best[1]*100:>7.0f}%{flag}")

# ---------------------------------------------------------------------------
# THE ESSENCE ECONOMY — every table that pays an essence against every recipe
# that spends one (2026-09-17). The owner, on a Hall's levels screen: "the
# 'halls' say mid essence? Is that only mid? What if I need others?" This is
# the measurement behind the answer in Docs/PLAN.md (*Essence tiers — the
# ladder an awakening should climb*), and since the evening of the same day,
# on the owner's word, the mirror of what ships: `recipe_shipped` is
# `UnitDatabase.awakeningCost(element:naturalStars:)`, the ONE function every
# awakening reads, and `HALL_ESSENCE_SHIPPED` is
# `DungeonDatabase.hallEssenceChances`. PLAN.md's own table (`recipe_ladder`,
# `HALL_ESSENCE_LADDER`) is kept as it was designed and the report ASSERTS
# what ships equals it; what the game paid before the ladder (`recipe_flat`,
# `HALL_ESSENCE_FLAT`) is kept as the "before", because the measurement
# against it is the reason the ladder exists. Every source below is read off
# StageDatabase and DungeonDatabase, not estimated.
ENERGY_PER_DAY = 24 * 60 // 5       # GameStore: one energy every five minutes
ELEMENTS = ["ember", "tide", "gale", "radiance", "umbra"]
ESSENCE_TIERS = ["low", "mid", "high"]
ESSENCE_IDS = ([f"essence_{e}_{t}" for e in ELEMENTS for t in ESSENCE_TIERS]
               + [f"essence_magic_{t}" for t in ESSENCE_TIERS])

TIER_DROP_SCALE = {"normal": 1.0, "hard": 1.4, "hell": 1.8}      # CampaignDifficulty.dropScale
TIER_ENERGY_EXTRA = {"normal": 0, "hard": 2, "hell": 4}         # CampaignDifficulty.energyExtra
HALL_ENERGY = lambda floor: 5 + floor                            # DungeonDatabase.hall
TITAN_ENERGY = 12                                                # StageDatabase.raids

# DungeonDatabase.hallEssenceChances, per floor, for the hall's own element:
# Low sure on B1-2 with Mid climbing, Mid sure on B3-4 with High climbing,
# B5 Mid sure and High at half. Change a chance there and here together.
HALL_ESSENCE_SHIPPED = {1: {"low": 1.0, "mid": 0.40}, 2: {"low": 1.0, "mid": 0.50},
                        3: {"mid": 1.0, "high": 0.25}, 4: {"mid": 1.0, "high": 0.35},
                        5: {"mid": 1.0, "high": 0.50}}
# PLAN.md's re-tiering as designed: Low on B1-2, Mid on B3-4, High on B5.
HALL_ESSENCE_LADDER = {1: {"low": 1.0, "mid": 0.40}, 2: {"low": 1.0, "mid": 0.50},
                       3: {"mid": 1.0, "high": 0.25}, 4: {"mid": 1.0, "high": 0.35},
                       5: {"mid": 1.0, "high": 0.50}}
# Before the ladder (to 2026-09-17): DungeonDatabase.hall paid Mid at
# min(1, 0.5 + 0.1f) and High at 0.1f, on every floor.
HALL_ESSENCE_FLAT = {f: {"mid": min(1.0, 0.5 + 0.1 * f), "high": 0.1 * f} for f in range(1, 6)}
# The Hall floor a grade is meant to farm: the report reads each recipe at it.
GRADE_FLOOR = {3: 1, 4: 3, 5: 5}


def recipe_shipped(element, stars):
    """UnitDatabase.awakeningCost(element:naturalStars:), by NATURAL grade: a
    5* asks 15 Mid and 10 High of its element with 10 Mid and 5 High Magic; a
    4* 10 Mid and 5 High with 8 and 3; a 3* 10 Low and 5 Mid with 5 Low and 5
    Mid Magic. Change a count there and here together."""
    e = lambda t: f"essence_{element}_{t}"
    if stars >= 5:
        return {e("mid"): 15, e("high"): 10, "essence_magic_mid": 10, "essence_magic_high": 5}
    if stars == 4:
        return {e("mid"): 10, e("high"): 5, "essence_magic_mid": 8, "essence_magic_high": 3}
    return {e("low"): 10, e("mid"): 5, "essence_magic_low": 5, "essence_magic_mid": 5}


def recipe_ladder(element, stars):
    """PLAN.md's ladder by natural grade, as designed."""
    e = lambda t: f"essence_{element}_{t}"
    if stars >= 5:
        return {e("mid"): 15, e("high"): 10, "essence_magic_mid": 10, "essence_magic_high": 5}
    if stars == 4:
        return {e("mid"): 10, e("high"): 5, "essence_magic_mid": 8, "essence_magic_high": 3}
    return {e("low"): 10, e("mid"): 5, "essence_magic_low": 5, "essence_magic_mid": 5}


def recipe_flat(element, stars):
    """Before the ladder: a 5* asked 15 Mid of its element, 10 Mid and 5 High
    Magic; anything else 10, 8 and 3. Nothing asked for Low or High of an
    element, and each hand-written blueprint carried its own dictionary."""
    if stars >= 5:
        return {f"essence_{element}_mid": 15, "essence_magic_mid": 10, "essence_magic_high": 5}
    return {f"essence_{element}_mid": 10, "essence_magic_mid": 8, "essence_magic_high": 3}


def essence_sources(halls):
    """Every FARMABLE source as (label, energy, {essence id: chance}). The
    tribute chests pay Mid Magic once per chapter tier and the bazaar sells
    Magic essence for drachma and divinity; both are listed by the report and
    neither is a farm, so neither is a row here."""
    rows = []
    for tier, scale in TIER_DROP_SCALE.items():
        extra = TIER_ENERGY_EXTRA[tier]
        # StageDatabase.duat1, hand-written: the game's only Low drops and the
        # boss's Mids; scaled by the tier like every generated stage.
        rows.append((f"Duat 1-3 {tier}", 4 + extra, {"essence_magic_low": min(1.0, 0.35 * scale)}))
        rows.append((f"Duat 1-4 {tier}", 4 + extra, {"essence_magic_low": min(1.0, 0.35 * scale),
                                                       "essence_umbra_low": min(1.0, 0.20 * scale)}))
        rows.append((f"Duat 1-5 {tier}", 6 + extra, {"essence_magic_mid": min(1.0, 0.50 * scale),
                                                       "essence_umbra_mid": min(1.0, 0.35 * scale)}))
        # generatedChapter: every other chapter drops Mid Magic, 20% a stage
        # and 60% at the boss, at 4 and 6 energy plus the tier's extra.
        rows.append((f"a chapter stage, {tier}", 4 + extra, {"essence_magic_mid": min(1.0, 0.2 * scale)}))
        rows.append((f"a chapter boss, {tier}", 6 + extra, {"essence_magic_mid": min(1.0, 0.6 * scale)}))
    for element in ELEMENTS:
        for floor, tiers in halls.items():
            rows.append((f"Hall of {element} B{floor}", HALL_ENERGY(floor),
                         {f"essence_{element}_{t}": c for t, c in tiers.items()}))
        # StageDatabase.raids: each Titan pays its element's High and High Magic.
        rows.append((f"Titan of {element}", TITAN_ENERGY,
                     {f"essence_{element}_high": 0.8, "essence_magic_high": 0.5}))
    return rows


def cheapest_sources(rows):
    """Per essence id: (energy per expected essence, source label), farming
    the one source that pays it cheapest, one essence at a time."""
    best = {}
    for label, energy, drops in rows:
        for essence, chance in drops.items():
            if chance <= 0:
                continue
            cost = energy / chance
            if essence not in best or cost < best[essence][0]:
                best[essence] = (cost, label)
    return best


def bill(recipe, best):
    """Expected energy to farm a recipe, every essence at its cheapest source."""
    return sum(needed * best[essence][0] for essence, needed in recipe.items() if essence in best)


def hall_road(recipe, element, halls, floor):
    """The element's own Hall at ONE floor: the runs that pay the recipe's
    elemental part (a run pays every tier it drops at once, so the runs are
    set by the slowest of them), or None where a needed tier never drops there."""
    runs = 0.0
    for essence, needed in recipe.items():
        if not essence.startswith(f"essence_{element}_"):
            continue
        tier = essence.rsplit("_", 1)[1]
        chance = halls[floor].get(tier, 0.0)
        if chance <= 0:
            return None
        runs = max(runs, needed / chance)
    return runs


def report_essences():
    print("\nTHE ESSENCE ECONOMY — what pays each essence, against what spends it")
    print(f"energy regenerates one every five minutes, {ENERGY_PER_DAY} a day; a bazaar refill is on top\n")

    # The mirror IS the design: what ships is asserted equal to PLAN.md's
    # table before anything is measured, so a drift in either file shows here.
    assert HALL_ESSENCE_SHIPPED == HALL_ESSENCE_LADDER, "the Halls do not pay PLAN.md's ladder"
    for element in ELEMENTS:
        for stars in (3, 4, 5):
            assert recipe_shipped(element, stars) == recipe_ladder(element, stars), \
                f"{element} {stars}*: the recipe is not PLAN.md's ladder"
    print("  as shipped == the ladder: the Halls' floors and every recipe are PLAN.md's table  -> correct\n")

    designs = [
        ("BEFORE THE LADDER (to 2026-09-17)", HALL_ESSENCE_FLAT, recipe_flat),
        ("AS SHIPPED — THE LADDER", HALL_ESSENCE_SHIPPED, recipe_shipped),
    ]
    results = {}
    for title, halls, recipe in designs:
        rows = essence_sources(halls)
        best = cheapest_sources(rows)
        spent = set()
        for element in ELEMENTS:
            for stars in (3, 4, 5):
                spent.update(recipe(element, stars).keys())
        dropped = set(best)
        orphans = sorted(dropped - spent)          # paid out, spent nowhere
        unsourced = sorted(spent - dropped)        # asked for, dropped nowhere
        idle = sorted(set(ESSENCE_IDS) - dropped - spent)   # in the catalogue only

        print(f"== {title} ==")
        print(f"  {'essence':<24}{'cheapest farm':>28}{'energy each':>13}   spent by")
        for essence in ESSENCE_IDS:
            sinks = sorted({f"{s}*" for e in ELEMENTS for s in (3, 4, 5) if essence in recipe(e, s)})
            farm = f"{best[essence][1]:>28}{best[essence][0]:>12.1f}" if essence in best else f"{'never drops':>28}{'':>12}"
            print(f"  {essence:<24}{farm}   {', '.join(sinks) or 'nothing'}")
        print(f"  dropped but never spent: {', '.join(orphans) or 'none'}")
        print(f"  spent but never dropped: {', '.join(unsourced) or 'none'}")
        print(f"  in the catalogue only:   {', '.join(idle) or 'none'}")

        print(f"\n  {'awakening':<12}{'cheapest, per essence':>24}{'the element at its own floor':>34}{'in days':>9}   cheapest floor")
        per_grade = {}
        floor_prices = {}
        for stars in (3, 4, 5):
            # Ember stands for every element: the five Halls are one recipe.
            r = recipe("ember", stars)
            cheapest = bill(r, best)
            floor = GRADE_FLOOR[stars]
            runs = hall_road(r, "ember", halls, floor)
            magic = sum(n * best[e][0] for e, n in r.items() if e.startswith("essence_magic_") and e in best)
            road = None if runs is None else runs * HALL_ENERGY(floor) + magic
            road_text = "-" if road is None else f"{runs:>5.1f} runs of B{floor} + magic = {road:>5.0f}"
            days = "-" if road is None else f"{road / ENERGY_PER_DAY:>7.2f}"
            # Every floor's price for the elemental part alone: which floor a
            # player who can clear them all should farm for this grade.
            prices = {}
            for f in range(1, 6):
                fr = hall_road(r, "ember", halls, f)
                if fr is not None:
                    prices[f] = fr * HALL_ENERGY(f)
            floor_prices[stars] = prices
            cheapest_floor = min(prices, key=prices.get)
            print(f"  {f'natural {stars}*':<12}{cheapest:>19.0f} energy{road_text:>34}{days:>9}   "
                  f"B{cheapest_floor} at {prices[cheapest_floor]:.0f}")
            per_grade[stars] = (cheapest, road, runs)
        # The five floors as five prices for a 5*'s elemental bill.
        p5 = floor_prices[5]
        print(f"  a 5*'s elemental bill, floor by floor (B1..B5): "
              + "  ".join(f"{p5[f]:>6.0f}" if f in p5 else "   -  " for f in range(1, 6)) + " energy")
        results[title] = (per_grade, orphans, unsourced, idle, floor_prices)
        print()

    before, ladder = results[designs[0][0]], results[designs[1][0]]
    # Before the ladder, every floor of a Hall was the same price for the
    # essence a 5* needed: Mid dropped at 0.1 x (5 + floor) for 5 + floor
    # energy, so a floor paid a tenth of a Mid per energy whatever its number,
    # and High, which climbed, was spent nowhere: five prices for one good.
    flat = len({round(p) for p in before[4][5].values()}) == 1
    print("  before the ladder: the Hall's five floors " + ("all cost the SAME per 5* awakening — the "
          "floors were not a ladder,\n  because Mid dropped at a tenth of an essence per energy on every one "
          "and the High that climbed was spent nowhere" if flat else "differed in price"))
    print(f"  before the ladder: {len(before[1])} essences dropped with nothing to spend them on "
          f"({', '.join(before[1])}) and {len(before[2])} were asked for but never dropped; "
          f"{len(before[3])} existed in the catalogue only")
    l3, l4, l5 = (ladder[0][s] for s in (3, 4, 5))
    s3 = before[0][3]
    print(f"  as shipped: a 3* {l3[1]:.0f} energy ({l3[1] / ENERGY_PER_DAY:.1f} days), "
          f"a 4* {l4[1]:.0f} ({l4[1] / ENERGY_PER_DAY:.1f}), a 5* {l5[1]:.0f} ({l5[1] / ENERGY_PER_DAY:.1f}); "
          f"the 3* was {s3[1]:.0f} before the ladder")

    # What ships is asserted; the state before it is only described, as the
    # reason the ladder exists.
    assert not ladder[1] and not ladder[2] and not ladder[3], "the ladder must give every essence a source and a sink"
    assert l3[1] < s3[1], "a 3* awakening must be CHEAPER under the ladder than before it (Low is the first floor's)"
    assert l3[1] < l4[1] < l5[1], "the ladder must climb with the grade"
    assert 0.8 <= l5[1] / ENERGY_PER_DAY <= 2.5, "a 5* awakening is days, not an afternoon and not a fortnight"
    assert l3[1] / ENERGY_PER_DAY <= 1.0, "a 3* awakening is a new account's day"
    # The floors are a ladder: a 3* is farmed on the Low floors (B1-2) and a
    # 5* on B5, and on the floors that pay a grade at all, the HIGHER floor is
    # the cheaper road — the climb pays, so a player who can clear B2 has a
    # reason to (B2 pays a 3*'s Mid at 50% for 7 energy against B1's 40% for
    # 6: 70 energy to 75; the first cut of this asserted B1 the cheapest and
    # the measurement said no).
    cost3, cost5 = ladder[4][3], ladder[4][5]
    assert min(cost3, key=cost3.get) in (1, 2), "a 3*'s cheapest floor must be a Low floor"
    assert min(cost5, key=cost5.get) == 5, "B5 must be the cheapest road to a 5*'s High"
    assert 1 not in cost5 and 2 not in cost5, "the Low floors must not pay a 5*'s bill at all"
    for prices in (cost3, cost5):
        floors = sorted(prices)
        assert all(prices[a] >= prices[b] for a, b in zip(floors, floors[1:])), \
            f"climbing must never cost more per awakening: {prices}"
    print("  -> as shipped: every essence has a source and a sink, the price climbs with the grade,")
    print("     a 3* farms the Low floors and a 5* farms B5, the higher floor is always the cheaper")
    print("     road, a 5* is days and a 3* is a day  -> correct")


# ---------------------------------------------------------------------------
# The event calendar (Core/Progression/EventCalendar.swift). Change a number
# in both files.
# ---------------------------------------------------------------------------
#
# A fixed weekday rota, a weekend headline seeded by the ISO week (counted
# continuously from Monday 1 January 2024, so the year's end never repeats a
# Hall), and every fourth week the Festival with a gift a day. Docs/EVENTS.md
# has the options and the choice; the point of the report is that a calendar
# is a set of multipliers on income, and multipliers that STACK are how a
# generous day becomes a broken one.
import datetime

EVENTS = {                       # EventTuning
    "drachma": 2.0,              # Monday: every settled clear's drachma
    "experience": 2.0,           # Tuesday: unit and summoner experience
    "energy": 0.5,               # Wednesday: a campaign stage's energy, rounded up
    "laurels": 2.0,              # Thursday: arena laurels, won or lost
    "essence": 2,                # the weekend's Hall: the AMOUNT of every essence roll
    "relics": 2,                 # the weekend's Labyrinth: the relic roll made this many times
}
EVENT_WEEKDAY_ROTA = ["drachma", "experience", "energy", "laurels"]   # EventCalendar.weekdayRota, Monday first
EVENT_WEEKEND_START = 4                                                # EventCalendar.weekendStart: Friday
EVENT_LABYRINTH_EVERY = 4                                              # EventCalendar.labyrinthEvery
EVENT_FESTIVAL_EVERY = 4                                               # EventCalendar.festivalEvery
EVENT_EPOCH = datetime.date(2024, 1, 1)                                # EventCalendar.epoch, a Monday
EVENT_HALLS = ELEMENTS                                                 # Element.allCases order
EVENT_LABYRINTHS = ["lab_colossus", "lab_hydra", "lab_necropolis"]     # DungeonDatabase.labyrinths order
EVENT_LABYRINTH_NAMES = {"lab_colossus": "the Vault of the Colossus", "lab_hydra": "the Lair of the Hydra",
                         "lab_necropolis": "the Necropolis of the Unwrapped King"}
# EventCalendar.festivalGifts, Monday to Sunday, priced in divinity-equivalent
# at the rates report_counsel uses: a pantheon scroll 100, a mystical 75, a
# 5* relic 150 (the bazaar's pack), drachma at DIVINITY_IN_DRACHMA, energy 1
# each.
EVENT_FESTIVAL_GIFTS = [
    ("15,000 drachma", 15_000 / DIVINITY_IN_DRACHMA), ("2 mystical scrolls", 150), ("40 energy", 40),
    ("100 divinity", 100), ("a pantheon scroll", 100), ("a 5* relic", 150),
    ("2 pantheon scrolls + 100 divinity", 300),
]
LOGIN_WEEK_VALUE = 473           # QuestService.loginGifts, the seven days, as report_counsel counts them
CAMPAIGN_ENERGY = 4              # generatedChapter: an ordinary stage's energy (a boss is 6)
CAMPAIGN_DRACHMA = lambda index: 900 + index * 220   # generatedChapter's drachma per clear


def event_week_index(day):
    """EventCalendar.weekIndex(at:): whole weeks since the epoch's Monday."""
    return (day - EVENT_EPOCH).days // 7


def event_headline(week):
    """EventCalendar.headline(week:): ('essence', element) or ('relics', labyrinth id)."""
    cycle = EVENT_LABYRINTH_EVERY
    if week % cycle == cycle - 1:
        return ("relics", EVENT_LABYRINTHS[(week // cycle) % len(EVENT_LABYRINTHS)])
    hall_weeks = week - week // cycle
    return ("essence", EVENT_HALLS[hall_weeks % len(EVENT_HALLS)])


def event_income_rows(week):
    """What each income pays PER ENERGY (per battle, for laurels) on each day
    of a week, Monday first, the way the game applies the rota: the campaign's
    half-energy day is twice the runs, so its drachma and experience per
    energy double that day too; the Halls and the Labyrinth keep their price
    and take only their own weekend."""
    headline = event_headline(week)
    runs = [1.0] * 7
    rows = {"campaign drachma / energy": [1.0] * 7, "campaign experience / energy": [1.0] * 7,
            "campaign drops / energy": [1.0] * 7, "arena laurels / battle": [1.0] * 7,
            "the weekend Hall's essence / energy": [1.0] * 7,
            "the weekend Labyrinth's relics / energy": [1.0] * 7}
    for day, kind in enumerate(EVENT_WEEKDAY_ROTA):
        if kind == "energy": runs[day] *= 1 / EVENTS["energy"]
        elif kind == "drachma": rows["campaign drachma / energy"][day] *= EVENTS["drachma"]
        elif kind == "experience": rows["campaign experience / energy"][day] *= EVENTS["experience"]
        elif kind == "laurels": rows["arena laurels / battle"][day] *= EVENTS["laurels"]
    for day in range(7):
        for key in ("campaign drachma / energy", "campaign experience / energy", "campaign drops / energy"):
            rows[key][day] *= runs[day]
    for day in range(EVENT_WEEKEND_START, 7):
        if headline[0] == "essence": rows["the weekend Hall's essence / energy"][day] *= EVENTS["essence"]
        else: rows["the weekend Labyrinth's relics / energy"][day] *= EVENTS["relics"]
    return rows


def report_events():
    """A week of the calendar, the multiplier matrix, and the two rules: no
    day stacks two events on one income, and no income's weekly mean exceeds
    2x — the lead's rule, "a full week of events never more than doubles a
    day's income on average"."""
    print("\nEVENTS — the calendar, deterministic from the date (EventCalendar.swift)")
    today = datetime.date.today()
    week = event_week_index(today)
    monday = today - datetime.timedelta(days=today.weekday())
    days = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    print(f"the week of {monday:%d %b %Y} (week {week} since the epoch's Monday), today {days[today.weekday()]}:")
    for day, kind in enumerate(EVENT_WEEKDAY_ROTA):
        what = {"drachma": f"drachma x{EVENTS['drachma']:g} on every settled clear",
                "experience": f"unit and summoner experience x{EVENTS['experience']:g}",
                "energy": f"campaign stages at x{EVENTS['energy']:g} energy, rounded up (3 -> 2, 4 -> 2, 6 -> 3)",
                "laurels": f"arena laurels x{EVENTS['laurels']:g}, won or lost"}[kind]
        print(f"  {days[day]:<4}{'*' if day == today.weekday() else ' '} {what}")
    kind, where = event_headline(week)
    span = f"{days[EVENT_WEEKEND_START]}-{days[6]}"
    what = (f"the Hall of {where} drops x{EVENTS['essence']} essence" if kind == "essence"
            else f"{EVENT_LABYRINTH_NAMES[where]} drops {EVENTS['relics']} relics a level")
    print(f"  {span:<4}{'*' if today.weekday() >= EVENT_WEEKEND_START else ' '} {what}")
    festival = week % EVENT_FESTIVAL_EVERY == EVENT_FESTIVAL_EVERY - 1
    print(f"  {'week':<4}  " + ("the FESTIVAL: a gift a day" if festival else
          f"no Festival; the next is in {EVENT_FESTIVAL_EVERY - 1 - week % EVENT_FESTIVAL_EVERY} week(s)"))

    print("\nthe next eight weekends:")
    seen_halls, seen_labs = set(), set()
    headlines = []
    for offset in range(1, 9):
        w = week + offset
        kind, where = event_headline(w)
        headlines.append((kind, where))
        (seen_halls if kind == "essence" else seen_labs).add(where)
        start = monday + datetime.timedelta(days=7 * offset + EVENT_WEEKEND_START)
        tag = " + Festival" if w % EVENT_FESTIVAL_EVERY == EVENT_FESTIVAL_EVERY - 1 else ""
        print(f"  {start:%d %b}  {'Hall of ' + where if kind == 'essence' else EVENT_LABYRINTH_NAMES[where]}{tag}")
    # The wheel: every Hall and every Labyrinth in turn, none twice running.
    full_cycle = [event_headline(week + o) for o in range(len(EVENT_HALLS) * EVENT_LABYRINTH_EVERY)]
    assert {h[1] for h in full_cycle if h[0] == "essence"} == set(EVENT_HALLS), "every Hall must get its weekend"
    assert {h[1] for h in full_cycle if h[0] == "relics"} == set(EVENT_LABYRINTHS), "every Labyrinth must get its weekend"
    assert all(a != b for a, b in zip(full_cycle, full_cycle[1:])), "no weekend repeats the one before"
    labyrinth_weeks = [o for o in range(EVENT_LABYRINTH_EVERY * 3) if event_headline(week + o)[0] == "relics"]
    assert len(labyrinth_weeks) == 3 and all(b - a == EVENT_LABYRINTH_EVERY for a, b in zip(labyrinth_weeks, labyrinth_weeks[1:])), \
        "a Labyrinth weekend every fourth week, on the beat"
    # The year's end does not repeat a Hall: week 52/53 into week 1 is a step
    # on the wheel like any other, because the index is counted, not read.
    for year in (2025, 2026, 2027):
        last = event_week_index(datetime.date(year, 12, 28))
        assert event_headline(last) != event_headline(last + 1), f"the wheel must not stall over {year}'s end"

    # The multiplier matrix, over a Hall week and a Labyrinth week: the
    # weekend's target is the one row that differs between them.
    print("\nwhat each income pays, per energy (laurels per battle):")
    print(f"  {'':<40}" + "".join(f"{d:>6}" for d in days) + f"{'mean':>8}")
    ceiling = max(EVENTS["drachma"], EVENTS["experience"], EVENTS["laurels"], EVENTS["essence"], EVENTS["relics"],
                  1 / EVENTS["energy"])
    hall_week = next(week + o for o in range(EVENT_LABYRINTH_EVERY) if event_headline(week + o)[0] == "essence")
    lab_week = next(week + o for o in range(EVENT_LABYRINTH_EVERY) if event_headline(week + o)[0] == "relics")
    lifted = {}
    for label, probe_week in (("a Hall week", hall_week), ("a Labyrinth week", lab_week)):
        print(f"  {label}:")
        for name, cells in event_income_rows(probe_week).items():
            mean = sum(cells) / 7
            print(f"  {name:<40}" + "".join(f"{c:>6.2f}" for c in cells) + f"{mean:>8.2f}")
            assert max(cells) <= ceiling + 1e-9, f"{name}: a day stacks two events ({max(cells):.2f}x)"
            assert mean <= 2.0, f"{name}: a week of events more than doubles the income on average ({mean:.2f}x)"
            lifted[name] = max(lifted.get(name, 1.0), mean)
    for name, best in lifted.items():
        assert best > 1.0, f"{name}: nothing on the calendar ever lifts it"
    # Every income has exactly ONE day-span: the rota names each kind once.
    assert sorted(EVENT_WEEKDAY_ROTA) == sorted(set(EVENT_WEEKDAY_ROTA)), "a kind twice in the rota is a stacked day"
    assert len(EVENT_WEEKDAY_ROTA) == EVENT_WEEKEND_START, "the weekdays hand over to the weekend where the rota ends"
    assert len(EVENT_WEEKDAY_ROTA) + (7 - EVENT_WEEKEND_START) == 7, "the rota must cover seven days"

    # In drachma: a mid-chapter stage at Normal, three-starred (the sweep's
    # gate, and what a farmer earns), on a flat day and on Monday.
    per_energy = CAMPAIGN_DRACHMA(5) * STAR_BONUS / CAMPAIGN_ENERGY
    flat_day = per_energy * ENERGY_PER_DAY
    print(f"\n  a chapter's fifth stage pays {CAMPAIGN_DRACHMA(5):,} drachma for {CAMPAIGN_ENERGY} energy,")
    print(f"  x{STAR_BONUS} three-starred: {per_energy:,.0f} a point of energy, {flat_day:,.0f} a day of {ENERGY_PER_DAY};")
    print(f"  Monday pays {flat_day * EVENTS['drachma']:,.0f}, Wednesday's half energy the same {flat_day * (1 / EVENTS['energy']):,.0f}"
          f" in twice the runs, and the week averages x{(5 + EVENTS['drachma'] + 1 / EVENTS['energy']) / 7:.2f}")

    # The Festival against the ordinary login week.
    total = sum(v for _, v in EVENT_FESTIVAL_GIFTS)
    print(f"\n  the Festival's seven gifts: " + ", ".join(f"{name} ({v:.0f})" for name, v in EVENT_FESTIVAL_GIFTS))
    print(f"  = {total:,.0f} divinity-equivalent, about {total / 100:.1f} pantheon summons, once every {EVENT_FESTIVAL_EVERY} weeks")
    print(f"  the ordinary login week is {LOGIN_WEEK_VALUE}; the Festival is x{total / LOGIN_WEEK_VALUE:.2f} of it, "
          f"{total / EVENT_FESTIVAL_EVERY:,.0f} a week averaged — {total / EVENT_FESTIVAL_EVERY / LOGIN_WEEK_VALUE * 100:.0f}% on top of the login gift")
    assert len(EVENT_FESTIVAL_GIFTS) == 7, "a gift a day for the week"
    assert total > LOGIN_WEEK_VALUE, "a special login week must beat the ordinary one, or it is not special"
    assert total / EVENT_FESTIVAL_EVERY < LOGIN_WEEK_VALUE, "averaged, the Festival must stay under a second login gift"
    print("  -> the rota covers seven days, every income has one day, nothing stacks, no weekly mean tops 2x,")
    print("     the wheel visits every Hall and every Labyrinth and never stalls over a year's end  -> correct")


# ---------------------------------------------------------------------------
# HIDDEN SHRINES AND SUMMONING PIECES (2026-09-23; Docs/SHRINES.md) — this
# section is the shrine feature's own. Summoners War's Secret Dungeon: a clear
# of a Labyrinth level or a Hall floor sometimes opens a hidden shrine for an
# hour, keyed to one family FORM (never Radiance or Umbra), and every win in
# it pays summoning pieces of that form — 20 summon a 3*, 40 a 4*, 100 a 5*.
# Mirrored from Pantheon/Core/PvE/ShrineService.swift and pinned in
# PantheonTests/ShrineTests.swift: change a number in all three.
SHRINE_DISCOVERY_PER_ENERGY = 0.005        # ShrineService.discoveryPerEnergy: a clear's chance per point of its energy
SHRINE_WINDOW_MINUTES = 60                 # ShrineService.windowMinutes: Summoners War's exact hour
SHRINE_MAX_OPEN = 3                        # ShrineService.maxOpen
SHRINE_PIECES_PER_SUMMON = {3: 20, 4: 40, 5: 100}   # ShrineService.piecesPerSummon
SHRINE_PIECES_PER_RUN = 3                  # ShrineService.piecesPerRun
SHRINE_BONUS_PIECE = 0.5                   # ShrineService.bonusPieceChance: a 4th piece one win in two
SHRINE_RETURN_CHANCE = 0.5                 # ShrineService.returnChance: a new shrine is a form you hold pieces of
SHRINE_GRADE_WEIGHTS = {                   # ShrineService.gradeWeights, by the found stage's relic grade
    3: {3: 0.75, 4: 0.24, 5: 0.01},        # Labyrinth B1-3, Hall B1
    4: {3: 0.63, 4: 0.35, 5: 0.02},        # Labyrinth B4-6, Hall B2
    5: {3: 0.53, 4: 0.43, 5: 0.04},        # Labyrinth B7-9, Hall B3-5
    6: {3: 0.44, 4: 0.51, 5: 0.05},        # Labyrinth B10
}
SHRINE_ESSENCE_CHANCE = 0.30               # ShrineService.essenceChance: the form's element, Mid
SHRINE_SCROLL_CHANCE = 0.10                # ShrineService.scrollChance: an Unknown Scroll
SHRINE_BOSS_MULTIPLIER = 1.6               # ShrineService.bossMultiplier, the Labyrinth boss's
SHRINE_FUSION_PRIZES = {"sekhmet_tide", "ares_gale", "horus_ember", "zeus_tide", "thoth_gale", "hades_ember"}  # FusionService.recipes
SHRINE_LAB_ENERGY = lambda level: 6 + level // 4                 # DungeonDatabase.labyrinth's energyCost
# What "normal play" is, stated so it can be argued with. The day's
# regenerated energy, three quarters of it in the Labyrinth and the Halls
# once the campaign is walked (the rest to the Tower, the Titans and Hard and
# Hell); the bar is the level's (80 + 2 a level, CampaignService), and a
# shrine is farmed with what an hour of it holds: the bar and an hour's
# regeneration. A 3* or 4* shrine is farmed until its unit is summoned; a 5*
# until the hour's energy runs out.
SHRINE_DUNGEON_SHARE = 0.75
SHRINE_PROFILES = [  # name, energy a clear, the found stage's relic grade, demigod level
    ("a new account, Hall B1", HALL_ENERGY(1), HALL_GRADE(1), 10),
    ("normal play, Labyrinth B7", SHRINE_LAB_ENERGY(7), LAB_GRADE(7), 30),
    ("normal play, Hall B3", HALL_ENERGY(3), HALL_GRADE(3), 30),
    ("the endgame, Labyrinth B10", SHRINE_LAB_ENERGY(10), LAB_GRADE(10), 50),
]
SHRINE_NORMAL = 1                          # the profile the shape is asserted on
# The free pulls a day on a pantheon banner, off QuestService: the missions'
# divinity (arena 30, summon 10, offering 10), the all-missions bonus (a
# Pantheon Scroll and 30 divinity) and the login week's 50 divinity and one
# Pantheon Scroll. Mileage pays a point a pull, so this is also its rate.
SHRINE_FREE_DIVINITY_A_DAY = 30 + 10 + 10 + 30 + 50 / 7
SHRINE_FREE_PANTHEON_A_DAY = 1 + 1 / 7
SHRINE_PANTHEON_RARE_PITY = 10             # Banner.olympusStirs (and three more) rarePity
SHRINE_ENERGY_DIVINITY = 30 / 30           # the bazaar's "Energy x30" is 30 divinity


def shrine_pool():
    """Forms a shrine can be keyed to, by grade: every family's fire, water
    and wind form (Banner.excludingLightDark over UnitDatabase.summonPool),
    less the fusion prizes the pool has never held. Radiance and Umbra are
    never in it — the Light & Dark scroll is their only road."""
    families = [(key, stars) for key, _, stars, *_ in FAMILY_ROWS] + [(key, bp.stars) for key, bp in HANDWRITTEN]
    pool = {3: [], 4: [], 5: []}
    for key, stars in families:
        for element in ("ember", "tide", "gale"):
            form = f"{key}_{element}"
            if form not in SHRINE_FUSION_PRIZES and stars in pool:
                pool[stars].append(form)
    return pool


def shrine_pieces_a_win():
    return SHRINE_PIECES_PER_RUN + SHRINE_BONUS_PIECE


def shrine_sim(energy, depth, level, days, seed, pool):
    """Normal play, day by day: the dungeon share of the day's energy spent
    a clear at a time; each clear's chance; a shrine's grade off its depth and
    its form off the stock rule; the shrine farmed at once with the hour's
    energy. Returns the shrines and units by grade, the energy the shrines
    took and the day the first 5* was summoned."""
    from collections import Counter
    rng = random.Random(seed)
    window = 80 + 2 * (level - 1) + SHRINE_WINDOW_MINUTES // ENERGY_MINUTES
    stock = {}
    shrines, units, spent = Counter(), Counter(), Counter()
    first_five = None
    weights = SHRINE_GRADE_WEIGHTS[depth]
    grades = sorted(weights)
    for day in range(days):
        left = ENERGY_PER_DAY * SHRINE_DUNGEON_SHARE
        while left >= energy:
            left -= energy
            if rng.random() >= energy * SHRINE_DISCOVERY_PER_ENERGY:
                continue
            grade = rng.choices(grades, weights=[weights[g] for g in grades])[0]
            held = [(form, n) for form, n in stock.items() if n > 0 and form in pool[grade]]
            if held and rng.random() < SHRINE_RETURN_CHANCE:
                form = rng.choices([f for f, _ in held], weights=[n for _, n in held])[0]
            else:
                form = rng.choice(pool[grade])
            shrines[grade] += 1
            budget = window
            price = SHRINE_PIECES_PER_SUMMON[grade]
            while budget >= energy and left >= energy:
                if grade < 5 and stock.get(form, 0) >= price:
                    break
                budget -= energy
                left -= energy
                spent[grade] += energy
                stock[form] = stock.get(form, 0) + SHRINE_PIECES_PER_RUN + (1 if rng.random() < SHRINE_BONUS_PIECE else 0)
            while stock.get(form, 0) >= price:
                stock[form] -= price
                units[grade] += 1
                if grade == 5 and first_five is None:
                    first_five = day + 1
    return shrines, units, spent, first_five


def shrine_pantheon_rates(pulls=200_000):
    """Mean pulls per 5* and per 4* on a pantheon banner — report_gacha's
    walk (hard pity 90, soft from 67) with the 4* guarantee at ten."""
    odds = SCROLL_ODDS["pantheonic"]
    rng = random.Random(7)
    since = rare = fives = fours = 0
    for _ in range(pulls):
        since += 1
        rare += 1
        r = rng.random()
        stars = 5 if r < odds[5] else (4 if r < odds[5] + odds[4] else 3)
        if since >= 90:
            stars = 5
        elif stars < 5 and since > 67 and rng.random() < min(0.9, (since - 67) * 0.06):
            stars = 5
        if stars < 4 and rare >= SHRINE_PANTHEON_RARE_PITY:
            stars = 4
        if stars >= 4:
            rare = 0
        if stars == 5:
            fives += 1
            since = 0
        elif stars == 4:
            fours += 1
    return pulls / fives, pulls / fours


def report_shrines(seeds=60, days=500, steady_days=5000):
    print("\nHIDDEN SHRINES — a clear's chance of an hour-long shrine, and the pieces it pays")
    pool = shrine_pool()
    sizes = {grade: len(forms) for grade, forms in pool.items()}
    print(f"  a clear finds one {SHRINE_DISCOVERY_PER_ENERGY * 100:.1f}% of the time for each point of energy it cost; "
          f"open {SHRINE_WINDOW_MINUTES} minutes, {SHRINE_MAX_OPEN} at most")
    print(f"  every win pays {SHRINE_PIECES_PER_RUN}, and a 4th {SHRINE_BONUS_PIECE * 100:.0f}% of the time "
          f"({shrine_pieces_a_win():.1f} a win); a summon takes "
          + ", ".join(f"{p} for a {g}*" for g, p in sorted(SHRINE_PIECES_PER_SUMMON.items())))
    print(f"  the forms a shrine can be: {sizes[3]} at 3*, {sizes[4]} at 4*, {sizes[5]} at 5* "
          f"(fire, water and wind; no Radiance, no Umbra, no fusion prize)")
    print(f"  a new shrine is a form you hold pieces of {SHRINE_RETURN_CHANCE * 100:.0f}% of the time, "
          "weighted by the pieces held — the rest a form of the pool at random")

    # The shape's own guards on the tables.
    for depth, weights in SHRINE_GRADE_WEIGHTS.items():
        assert abs(sum(weights.values()) - 1) < 1e-9, f"depth {depth}: the grade weights must sum to 1"
        assert weights[5] <= 0.05, f"depth {depth}: a 5* shrine is rare (5% at most)"
        assert weights[3] + weights[4] >= 0.95, f"depth {depth}: shrines are weighted toward 3* and 4*"
    assert all(not form.endswith(("_radiance", "_umbra")) for forms in pool.values() for form in forms), \
        "no shrine is ever a Radiance or an Umbra form"
    assert not any(form in SHRINE_FUSION_PRIZES for forms in pool.values() for form in forms)

    # Scrolls, for the comparison: the random unit of a grade and the named one.
    per_five, per_four = shrine_pantheon_rates()
    pull = SCROLL_DIVINITY["pantheonic"]
    random_cost = {3: 5_000 / DIVINITY_IN_DRACHMA, 4: per_four * pull, 5: per_five * pull}
    random_source = {3: "an Unknown Scroll", 4: "a pantheon banner", 5: "a pantheon banner"}
    named_cost = {g: mileage_price(g, "pantheonic") * pull for g in (3, 4, 5)}
    free_pulls = SHRINE_FREE_PANTHEON_A_DAY + SHRINE_FREE_DIVINITY_A_DAY / pull

    print(f"\n  a unit by pieces, farmed at {SHRINE_PROFILES[SHRINE_NORMAL][0]} "
          f"({SHRINE_PROFILES[SHRINE_NORMAL][1]} energy a win; energy at the bazaar's {SHRINE_ENERGY_DIVINITY:.0f} divinity each),")
    print("  against the scrolls' expected cost of the same grade:")
    print(f"  {'grade':>5}{'pieces':>8}{'wins':>7}{'energy':>8}   {'a random one by scroll':<42}{'a NAMED one by mileage':>24}")
    normal_energy = SHRINE_PROFILES[SHRINE_NORMAL][1]
    unit_energy = {}
    for grade in (3, 4, 5):
        wins = SHRINE_PIECES_PER_SUMMON[grade] / shrine_pieces_a_win()
        energy = wins * normal_energy
        unit_energy[grade] = energy
        scroll_words = f"{random_cost[grade]:,.0f} divinity ({random_source[grade]})"
        print(f"  {grade:>4}*{SHRINE_PIECES_PER_SUMMON[grade]:>8}{wins:>7.1f}{energy:>8.0f}   "
              f"{scroll_words:<42}{named_cost[grade]:>15,.0f} divinity")
    print("  -> pieces are CHEAP in energy and DEAR in time: the energy a unit costs is small because the")
    print("     form is not chosen and its shrine is rare; what a player waits on is the shrine, so the")
    print("     honest comparison is in days of normal play, below.")

    # Normal play, simulated.
    print(f"\n  normal play: {ENERGY_PER_DAY} energy a day, {SHRINE_DUNGEON_SHARE * 100:.0f}% of it in the Labyrinth and the Halls, "
          f"every shrine farmed at once with an hour's energy (the bar and {SHRINE_WINDOW_MINUTES // ENERGY_MINUTES} regenerated)")
    print(f"  {'profile':<28}{'a clear':>8}{'shrines/day':>12}{'3*/wk':>7}{'4*/wk':>7}{'5*/wk':>7}"
          f"{'energy/day':>11}{'5* shrine':>10}{'first 5*':>10}")
    measured = []
    for index, (name, energy, depth, level) in enumerate(SHRINE_PROFILES):
        shrines, units, spent, _ = shrine_sim(energy, depth, level, steady_days, 90 + index, pool)
        firsts = sorted((shrine_sim(energy, depth, level, days, seed, pool)[3] or days * 2) for seed in range(seeds))
        first = statistics.median(firsts)
        per_day = sum(shrines.values()) / steady_days
        five_every = steady_days / max(1, shrines[5])
        measured.append((name, per_day, units, spent, first, five_every))
        print(f"  {name:<28}{energy * SHRINE_DISCOVERY_PER_ENERGY * 100:>7.1f}%{per_day:>12.2f}"
              + "".join(f"{units[g] / steady_days * 7:>7.2f}" for g in (3, 4, 5))
              + f"{sum(spent.values()) / steady_days:>11.0f}{five_every:>8.0f} d{first:>8.0f} d")

    name, per_day, units, spent, first, _ = measured[SHRINE_NORMAL]
    named_days = mileage_price(5, "pantheonic") / free_pulls
    random_days = per_five / free_pulls
    five_days = steady_days / max(1, units[5])
    level = SHRINE_PROFILES[SHRINE_NORMAL][3]
    window = 80 + 2 * (level - 1) + SHRINE_WINDOW_MINUTES // ENERGY_MINUTES
    endgame_window = 80 + 2 * (SHRINE_PROFILES[-1][3] - 1) + SHRINE_WINDOW_MINUTES // ENERGY_MINUTES
    endgame_energy = SHRINE_PIECES_PER_SUMMON[5] / shrine_pieces_a_win() * SHRINE_PROFILES[-1][1]
    print(f"\n  the free pulls a day on a pantheon banner: {free_pulls:.2f} (the missions, their bonus and the login week)")
    print(f"  a named 5* by mileage ({mileage_price(5, 'pantheonic')} points): {named_days:.0f} days; "
          f"a random 5* from the same pulls: every {random_days:.0f} days")
    print(f"  a 5* by pieces at {name}: the first in {first:.0f} days (the median of {seeds} players), "
          f"then one every {five_days:.0f} days")
    print(f"  a 4* by pieces: {unit_energy[4]:.0f} energy, inside one shrine's hour ({window} at level {level}); "
          f"a 5*: {endgame_energy:.0f} at B10, more than an endgame hour's {endgame_window} — it takes a shrine that comes back")

    # The shape.
    assert 0.6 <= per_day <= 1.2, f"about one shrine a day of normal play ({per_day:.2f})"
    assert unit_energy[3] * SHRINE_ENERGY_DIVINITY > random_cost[3], "the shrine must never be the cheapest fodder"
    assert unit_energy[4] <= window, "a 4* is one shrine's hour of normal play"
    assert endgame_energy > endgame_window, "no 5* is ever had from one shrine, however big the bar"
    assert first > named_days, "a 5* by pieces is slower than naming one by mileage"
    # And at every depth, the endgame's B10 included (the sim draws a Hall's
    # shrine from the whole pool, not its element's third, which makes a
    # Hall's forms come back LESS often than they will: a floor, not a
    # forecast).
    for profile_name, _, _, _, profile_first, _ in measured:
        assert profile_first > named_days, f"{profile_name}: a 5* by pieces is slower than mileage"
    assert five_days > 2 * random_days, "pieces are a supplement to the 5*s the free pulls bring, never the road"
    energy_share = sum(spent.values()) / steady_days / (ENERGY_PER_DAY * SHRINE_DUNGEON_SHARE)
    assert energy_share < 0.25, "the shrines take a share of the dungeon energy, never most of it"
    print(f"  the shrines take {energy_share * 100:.0f}% of normal play's dungeon energy; the rest still hunts relics and essences")
    print("  -> about one shrine a day, one 4* a shrine's hour, fodder dearer than an Unknown Scroll,")
    print("     and a 5* by pieces slower than naming one by mileage  -> correct")


if __name__ == "__main__":
    a = sys.argv[1:]
    if "--tune" in a: report_tune()
    elif "--curve" in a: report_curve()
    elif "--gacha" in a: report_gacha()
    elif "--families" in a: report_families()
    elif "--variants" in a: report_variants()
    elif "--chapters" in a: report_chapters()
    elif "--tiers" in a: report_tiers()
    elif "--halls" in a: report_halls()
    elif "--labyrinths" in a: report_labyrinths()
    elif "--tower" in a: report_tower()
    elif "--raids" in a: report_raids()
    elif "--grades" in a: report_grades()
    elif "--awakening" in a: report_awakening()
    elif "--boons" in a: report_boons()
    elif "--resonance" in a: report_resonance()
    elif "--regalia" in a: report_regalia()
    elif "--relics" in a: report_relics()
    elif "--tributes" in a: report_tributes()
    elif "--shop" in a: report_shop()
    elif "--counsel" in a: report_counsel()
    elif "--sweep" in a: report_sweep()
    elif "--mileage" in a: report_mileage()
    elif "--targeting" in a: report_targeting()
    elif "--drops" in a: report_drops()
    elif "--essences" in a: report_essences()
    elif "--events" in a: report_events()
    elif "--shrines" in a: report_shrines()
    else:
        report_curve(); report_elements(); report_duel(); report_campaign(); report_families(); report_chapters(); report_halls()
        report_labyrinths(); report_tower(); report_raids(); report_grades(); report_awakening(); report_boons()
        report_resonance(); report_regalia()
        report_gacha(); report_economy(); report_relics(); report_shop(); report_counsel()
        report_sweep(); report_mileage(); report_targeting(); report_essences(); report_events()
        report_shrines()
        print()
