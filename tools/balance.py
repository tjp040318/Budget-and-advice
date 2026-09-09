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

import math, random, re, statistics, sys
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
    burn: int = 0
    stun: int = 0

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

def proc(name, keyword, default):
    """Chance of an on-hit effect, read off the skill's name: "(Burn)" means the
    default, "(Burn 35%)" means 35%. Keeps the sim's numbers next to the kit's."""
    m = re.search(keyword + r"\s*(\d+)%", name, re.IGNORECASE)
    return int(m.group(1)) / 100 if m else default

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
        # Burn ticks at the start of the burning unit's turn for a flat 5% of
        # max HP, ignoring defence — BattleEngine.swift, "Burn ticks for a
        # flat share of max HP". Two turns per application.
        if actor.burn > 0:
            actor.hp -= actor.maxhp * 0.05
            actor.burn -= 1
            if not actor.alive: continue
        # Hard control consumes the turn: BattleEngine skips a stunned, frozen
        # or sleeping unit's action and ticks the status down.
        if actor.stun > 0:
            actor.stun -= 1
            continue

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
        # An AoE is worth its multiplier times the bodies it hits, which is
        # how AIController values it too; without this no ultimate that hits
        # the line for less than the basic's total would ever be cast.
        idx = max(dmg_ready, key=lambda i: actor.bp.skills[i][1] * actor.bp.skills[i][2]
                  * (len(foes) if actor.bp.skills[i][6] else 1))
        name, mult, hits, cd, defign, missbonus, aoe = actor.bp.skills[idx]
        actor.cds[idx] = cd
        targets = foes if aoe else [min(foes, key=lambda f: f.hp)]
        for _ in range(hits):
            for t in targets:
                if not t.alive: continue
                t.hp -= resolve_hit(actor, t, mult, defign, missbonus, rng)
                if "break" in name.lower(): t.defbreak = 2
                if "burn" in name.lower() and rng.random() < proc(name, "burn", 0.30): t.burn = 2
                if "stun" in name.lower() and rng.random() < proc(name, "stun", 0.55): t.stun = 1
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
# The summonable Shabti family: the gacha's 3* tier and the training hall's
# fodder. A two-skill servant a grade under Anubis; the Umbra one is the
# archetype and the other four are within ten percent of it.
SHABTI3   = Blueprint("shabti_umbra", "Shabti (Dark)",   "umbra",    3, 300, 25, 20,  98,
    skills=[("Clay Grasp", 1.60, 1, 0, 0, 0, False), ("Answer the Call", 2.30, 1, 3, 0, 0, False)])
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
# trade a little attack for health and swap the stun for a freeze, a sleep, an
# attack-bar knockback or a provoke, none of which the sim models yet.
ZEUS = Blueprint("zeus_ember", "Zeus (Fire)", "ember", 5, hp=445, atk=36, dfn=25, spd=105, acc=0.10,
    skills=[("Thunderbolt (Burn 35%)", 3.10, 1, 0, 0.0, 0.0, False),
            ("Thunderclap (Stun 55%)", 2.00, 1, 4, 0.0, 0.0, True),
            ("Keraunos", 5.00, 1, 5, 0.40, 0.0, False)])

# The second roster. Kits as in Pantheon/Core/Data/UnitDatabase+Roster.swift;
# the sim reads burn and stun off the skill names and nothing else, so a
# provoke, a heal or a shield shows up here only as the damage it does not do.
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
            ("Mirror Shield", 0.0, 0, 4, 0.0, 0.0, False),
            ("Gorgon's Gaze (Stun 45%)", 2.20, 1, 5, 0.0, 0.0, True)])
THOTH = Blueprint("thoth_ember", "Thoth (Fire)", "ember", 5, hp=520, atk=26, dfn=30, spd=108, acc=0.15, res=0.20,
    skills=[("Reed Stroke (Burn 35%)", 2.60, 1, 0, 0.0, 0.0, False),
            ("Words of Healing", 0.0, 0, 4, 0.0, 0.0, False),
            ("Book of the Dead", 0.0, 0, 5, 0.0, 0.0, False)])
HOPLITE = Blueprint("hoplite_ember", "Hoplite (Fire)", "ember", 3, hp=340, atk=22, dfn=26, spd=96,
    skills=[("Spear Jab (Burn 25%)", 1.70, 1, 0, 0.0, 0.0, False), ("Phalanx", 0.0, 0, 4, 0.0, 0.0, False)])
SATYR = Blueprint("satyr_ember", "Satyr (Fire)", "ember", 3, hp=300, atk=22, dfn=20, spd=104,
    skills=[("Hoof Kick (Burn 25%)", 1.70, 1, 0, 0.0, 0.0, False), ("Wild Piping", 0.0, 0, 4, 0.0, 0.0, False)])
HARPY = Blueprint("harpy_ember", "Harpy (Fire)", "ember", 3, hp=270, atk=28, dfn=16, spd=112,
    skills=[("Talon Rake (Burn 25%)", 1.00, 2, 0, 0.0, 0.0, False), ("Screech Dive", 2.60, 1, 3, 0.0, 0.0, False)])


# The third roster: Pantheon/Core/Data/UnitDatabase+Families.swift, one row per
# family and one of eight kit shapes, mirrored here row for row. The sim sees
# the fire variant (attack x1.05) and reads burn, stun and defence break off
# the skill names; heals, shields, provokes and strips show up only as the
# damage they do not do, so a healer's row is a floor, not a forecast.
def kit_skills(kit, stars, hp, atk):
    if kit == "striker":
        s = [("Strike (Burn 30%)", 3.00, 1, 0, 0, 0, False), ("Two Blows (Def Break 40%)", 2.10, 2, 3, 0, 0, False),
             ("Finisher", 2.70, 1, 5, 0, 0, True)]
    elif kit == "duelist":
        s = [("Two Cuts (Burn 30%)", 1.50, 2, 0, 0, 0, False), ("Piercing Blow", 4.60, 1, 4, 0.40, 0, False),
             ("Sure Crit", 5.40, 1, 5, 0, 0, False)]
    elif kit == "marksman":
        s = [("Shot (Burn 30%)", 2.90, 1, 0, 0, 0, False), ("Spread", 1.70, 3, 3, 0, 0, False),
             ("Volley (Stun 35%)", 2.40, 1, 5, 0, 0, True)]
    elif kit == "bruiser":
        s = [("Strike (Burn 30%)", 2.80, 1, 0, 0, 0, False), ("Roar", 1.50, 1, 4, 0, 0, True),
             ("Body Blow", 0.28 * hp / atk, 1, 4, 0.30, 0, False)]
    elif kit == "warden":
        s = [("Strike (Burn 30%)", 2.70, 1, 0, 0, 0, False), ("Shield Wall", 0.0, 0, 4, 0, 0, False),
             ("Counter Stance", 3.60, 1, 5, 0, 0, False)]
    elif kit == "healer":
        s = [("Strike (Burn 30%)", 2.50, 1, 0, 0, 0, False), ("Team Heal", 0.0, 0, 4, 0, 0, False),
             ("Blessing", 0.0, 0, 5, 0, 0, False)]
    elif kit == "oracle":
        s = [("Strike (Burn 30%)", 2.60, 1, 0, 0, 0, False), ("Control (Stun 40%)", 1.60, 1, 4, 0, 0, True),
             ("Surge", 0.0, 0, 5, 0, 0, False)]
    else:  # trickster
        s = [("Strike (Burn 40%)", 2.80, 1, 0, 0, 0, False), ("Strip", 3.40, 1, 3, 0, 0, False),
             ("Break (Def Break 60%)", 2.00, 1, 5, 0, 0, True)]
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
]

def generated_stage(chapter, index):
    _, start, step, stages, scale, roster, boss, stars, difficulty = chapter
    is_boss = index == stages
    level = start + (index - 1) * step
    n = 4 if is_boss else min(4, 2 + index // 3)
    spec = []
    for slot in range(n):
        last = is_boss and slot == n - 1
        bp = boss if last else roster[(index + slot) % len(roster)]
        grade = max(stars or bp.stars, bp.stars) if last else (stars or bp.stars)
        spec.append((bp, level, grade, difficulty * (1.4 if last else 1.0)))
    return spec, int(2500 * scale * 1.18 ** (index - 1))

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
            spec, power = generated_stage(ch, index)
            label = ch[0] + (" BOSS" if index == ch[3] else f" -{index}")
            row = f"{label:>36}{spec[0][1]:>5}{power:>9}  "
            for _, team in CHAPTER_LADDERS:
                wr, med = winrate(team, spec, trials=trials)
                row += f"{wr*100:>16.0f}% {med:>3.0f}t"
            print(row)

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
    ("Vault of the Colossus",      [SHABTI, SCARAB, SERPOPARD], SENTINEL),
    ("Lair of the Hydra",          [E_MEDUSA, SERPOPARD, E_AMAZON], HYDRA),
    ("Necropolis of the Devourer", [E_DRAUGR, SHABTI, SCARAB], AMMIT),
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
    print(f"{'level':>30}{'lvl':>5}  " + "".join(f"{n:>22}" for n, _ in LABYRINTH_LADDERS))
    for lab in LABYRINTHS:
        for level in (1, 4, 7, 10):
            waves = labyrinth_waves(lab, level)
            row = f"{lab[0] + f' B{level}':>30}{waves[0][0][1]:>5}  "
            for _, team in LABYRINTH_LADDERS:
                wr, med = winrate_waves(team, waves, trials=trials)
                row += f"{wr*100:>16.0f}% {med:>3.0f}t"
            print(row)

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
    elif "--families" in a: report_families()
    elif "--chapters" in a: report_chapters()
    elif "--halls" in a: report_halls()
    elif "--labyrinths" in a: report_labyrinths()
    else:
        report_curve(); report_elements(); report_duel(); report_campaign(); report_families(); report_chapters(); report_halls()
        report_labyrinths()
        report_gacha(); report_economy()
        print()
