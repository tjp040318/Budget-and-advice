#!/usr/bin/env python3
"""The Codex against the economy (Docs/CODEX.md, *What the book pays*).

Reads the family table out of the Swift (the 88 rows of
UnitDatabase+Families.swift and the eleven hand-written families), builds
every page of the book as CodexService does, prices the whole book with the
table below, and plays a first month and a first year of pulls — forty runs
each, the scrolls' real odds and pools — to measure what the book pays in
those windows against what the rest of the game pays in them.

The table MIRRORS `CodexService` (formDivinity, awakenedDivinity,
familyFirstDivinity, premiumMultiple, prize(for:)): change a number there,
here, in Docs/CODEX.md and in CodexTests together. It belongs in
tools/balance.py as `--codex`; it stands alone because the Codex was built
beside six other features on 2026-09-23 and balance.py was another's file
that day.

    python3 tools/codex_calib.py

Exits non-zero if the book stops being a bonus: a first month over 10% of the
month's income, or a first year over 5%.
"""
import random, re, sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# ---- the table (CodexService) ----
FORM = {3: 5, 4: 10, 5: 25}            # divinity per form, by natural grade
AWAKENED = {4: 20, 5: 40}              # divinity per awakened face
FAMILY_FIRST = {3: 5, 4: 20, 5: 50}    # the first page of a family claimed
PREMIUM = 2                            # Radiance and Umbra pages
# Divinity-equivalent at the bazaar's prices, as balance.py --counsel counts.
DE = {"pantheonic": 100, "mystical": 75, "divine": 600, "light_dark": 450, "unknown": 5000 / 300}
TIERS = {25: ("pantheonic", 1, 100), 50: ("divine", 1, 0), 75: ("light_dark", 1, 300), 100: ("light_dark", 3, 1000)}

# ---- the roster ----
src = (ROOT / "Pantheon/Core/Data/UnitDatabase+Families.swift").read_text()
ROWS = [(m.group(1), m.group(2), int(m.group(3)), m.group(4) != "nil") for m in re.finditer(
    r'FamilyRow\(key: "([^"]+)", name: "[^"]+", pantheon: \.(\w+), stars: (\d)[^\n]*\n(?:[^\n]*\n){2}\s*awakened: (nil|\[)',
    src)]
assert len(ROWS) == 88, f"the table has {len(ROWS)} rows; the reader expects 88"
HAND = [("anubis", "egyptian", 4, True), ("sekhmet", "egyptian", 5, True), ("thoth", "egyptian", 5, True),
        ("shabti", "egyptian", 3, False), ("zeus", "greek", 5, True), ("ares", "greek", 5, True),
        ("heracles", "greek", 4, True), ("perseus", "greek", 4, True), ("hoplite", "greek", 3, False),
        ("satyr", "greek", 3, False), ("harpy", "greek", 3, False)]
FAMILIES = HAND + ROWS
ELEMENTS = ["ember", "tide", "gale", "radiance", "umbra"]
PREMIUM_ELEMENTS = {"radiance", "umbra"}
FUSION_ONLY = {"sekhmet_tide", "ares_gale", "horus_ember", "zeus_tide", "thoth_gale", "hades_ember"}
PANTHEONS = ["egyptian", "greek", "norse", "roman", "chinese"]

# (blueprint id, pantheon, family, grade, element, face)
PAGES = []
for key, pantheon, stars, awakenable in FAMILIES:
    for element in ELEMENTS:
        PAGES.append((f"{key}_{element}", pantheon, key, stars, element, "form"))
        if awakenable:
            PAGES.append((f"{key}_{element}", pantheon, key, stars, element, "awakened"))
PER_PANTHEON = Counter(p[1] for p in PAGES)


def page_value(page):
    _, _, _, stars, element, face = page
    plain = FORM[stars] if face == "form" else AWAKENED[stars]
    return plain * (PREMIUM if element in PREMIUM_ELEMENTS else 1)


# ---- the pools the scrolls draw from (Banner, excludingLightDark) ----
def pool(keep, premium=False):
    out = defaultdict(list)
    for key, pantheon, stars, _ in FAMILIES:
        for element in ELEMENTS:
            bid = f"{key}_{element}"
            if bid in FUSION_ONLY or (element in PREMIUM_ELEMENTS) != premium:
                continue
            if keep(pantheon, stars):
                out[stars].append(bid)
    return out


ODDS = {"mystical": {3: .885, 4: .10, 5: .015}, "pantheonic": {3: .79, 4: .18, 5: .03},
        "unknown": {3: 1.0}, "light_dark": {3: .902, 4: .09, 5: .008}}
POOLS = {"mystical": pool(lambda p, s: True), "unknown": pool(lambda p, s: s == 3),
         "light_dark": pool(lambda p, s: True, premium=True)}
for name in PANTHEONS:
    POOLS["pantheon_" + name] = pool(lambda p, s, name=name: p == name)


def pull(kind, rng, pity):
    odds = ODDS["pantheonic" if kind.startswith("pantheon_") else kind]
    pity[kind] = pity.get(kind, 0) + 1
    roll, reach, grade = rng.random(), 0.0, 3
    for g in sorted(odds):
        reach += odds[g]
        if roll <= reach:
            grade = g
            break
    if kind.startswith("pantheon_") and pity[kind] >= 90:   # the banners' hard pity
        grade = 5
    if grade == 5:
        pity[kind] = 0
    choices = POOLS[kind][grade] or POOLS[kind][max(POOLS[kind])]
    return rng.choice(choices)


# A first month's pulls from the game's own sources: the daily missions'
# three Unknown, one Mystical and one Pantheon Scroll a day, the login gift,
# Athena's Counsel, the chapter clears and the starting wallet, with the
# month's divinity spent on Pantheon Scrolls at 100.
MONTH = {"unknown": 110, "mystical": 55, "pantheonic": 110, "light_dark": 1}
MONTH_FLOOR = 13_961   # balance.py --counsel: first clears, Normal and Hard chests, the login gift
MISSIONS = 30 * (3 * DE["unknown"] + 75 + 30 + 10 + 5000 / 300 + 10 + 10 + 130)   # QuestService, a day of it


def play(months, awakenings_a_month, rng):
    owned, pity = set(), {}
    for _ in range(months):
        for kind, count in MONTH.items():
            for _ in range(count):
                banner = kind
                if kind == "pantheonic":
                    banner = "pantheon_" + rng.choice(PANTHEONS[:3] * 3 + PANTHEONS[3:])
                owned.add(pull(banner, rng, pity))
    awakenable = sorted((p for p in PAGES if p[5] == "awakened" and p[0] in owned), key=lambda p: -p[3])
    awakened = {p[0] for p in awakenable[: awakenings_a_month * months]}
    return owned, awakened


def payout(owned, awakened):
    forms = sum(page_value(p) for p in PAGES if p[5] == "form" and p[0] in owned)
    faces = sum(page_value(p) for p in PAGES if p[5] == "awakened" and p[0] in awakened)
    families = {bid.rsplit("_", 1)[0] for bid in owned}
    firsts = sum(FAMILY_FIRST[f[2]] for f in FAMILIES if f[0] in families)
    tiers, reached = 0.0, []
    for name in PANTHEONS:
        lit = sum(1 for p in PAGES if p[1] == name and
                  ((p[5] == "form" and p[0] in owned) or (p[5] == "awakened" and p[0] in awakened)))
        for share, (scroll, count, divinity) in TIERS.items():
            if lit >= (PER_PANTHEON[name] * share + 99) // 100:
                tiers += DE[scroll] * count + divinity
                reached.append(f"{name}:{share}")
    return len(owned), len(families), len(awakened), forms, faces, firsts, tiers, reached


def main():
    forms = sum(page_value(p) for p in PAGES if p[5] == "form")
    faces = sum(page_value(p) for p in PAGES if p[5] == "awakened")
    firsts = sum(FAMILY_FIRST[f[2]] for f in FAMILIES)
    tier_one = sum(DE[s] * n + d for s, n, d in TIERS.values())
    premium_pages = sum(page_value(p) for p in PAGES if p[4] in PREMIUM_ELEMENTS)
    print("THE CODEX — the whole book")
    print(f"  {len(FAMILIES)} families, {sum(1 for p in PAGES if p[5] == 'form')} forms, "
          f"{sum(1 for p in PAGES if p[5] == 'awakened')} awakened faces; pages by pantheon {dict(PER_PANTHEON)}")
    print(f"  forms {forms:,} + awakened {faces:,} + families' firsts {firsts:,} = {forms + faces + firsts:,} divinity"
          f" ({premium_pages:,} of it on Radiance and Umbra pages)")
    print(f"  tiers {tier_one * len(PANTHEONS):,.0f} divinity-equivalent ({tier_one:,.0f} a pantheon)")
    print(f"  everything: about {forms + faces + firsts + tier_one * len(PANTHEONS):,.0f}")
    assert (forms, faces, firsts) == (8_225, 12_600, 2_190), "the book moved: re-measure, and move CodexTests with it"

    print(f"\n  a month's income: {MONTH_FLOOR:,} (balance.py --counsel) + {MISSIONS:,.0f} daily missions")
    ok = True
    for label, months, awakenings, ceiling in (("first month", 1, 1, 0.10), ("first year", 12, 2, 0.05)):
        runs = [payout(*play(months, awakenings, random.Random(seed))) for seed in range(40)]
        mean = lambda i: sum(r[i] for r in runs) / len(runs)
        paid = mean(3) + mean(4) + mean(5) + mean(6)
        income = months * (MONTH_FLOOR + MISSIONS)
        share = paid / income
        hits = Counter(t for r in runs for t in r[7])
        print(f"  {label}: {mean(0):.0f} forms of {mean(1):.0f} families, {mean(2):.0f} awakened -> "
              f"{mean(3):,.0f} + {mean(4):,.0f} + firsts {mean(5):,.0f} + tiers {mean(6):,.0f} = {paid:,.0f}; "
              f"{share * 100:.1f}% of {income:,.0f} ({paid / (months * MONTH_FLOOR) * 100:.1f}% of the floor)")
        if hits:
            print("    tiers reached:", ", ".join(f"{k} {v / len(runs):.0%}" for k, v in sorted(hits.items())))
        if share > ceiling:
            ok = False
            print(f"    OVER {ceiling:.0%}: the book is an income, not a bonus — cut the table")
    print("  -> a bonus, not an income" if ok else "  -> CUT THE TABLE")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
